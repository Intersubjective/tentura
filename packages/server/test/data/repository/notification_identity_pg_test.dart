@Tags(['pg'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/notification_identity_repository.dart';
import 'package:tentura_server/domain/notification/notification_identity.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';
import '../../support/query_counter.dart';

/// Notification identity resolver: what a recipient may see of a Request /
/// Post label and of the actor name, resolved in one batch.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_NOTIFICATION_IDENTITY_TEST_DB',
    defaultNamePrefix: 'tentura_test_notification_identity',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('NotificationIdentityRepository', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb db;
    late QueryCounter counter;
    late NotificationIdentityPort identities;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        writer = session.writer;
        counter = QueryCounter();
        db = TenturaDb.forTest(
          database: PgDatabase.opened(
            Pool<dynamic>.withEndpoints(
              [target.databaseEnv.pgEndpoint],
              settings: target.databaseEnv.pgPoolSettings,
            ),
            enableMigrations: false,
          ).interceptWith(counter),
        );
        identities = NotificationIdentityRepository(db);
        await _seed(writer);
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: db);
      });
    }

    Future<NotificationIdentity> one(
      String recipient,
      String beaconId, {
      String? actorId,
      String? relatedBeaconId,
    }) async {
      final result = await identities.resolve(recipient, [
        IdentityRequest(
          beaconId: beaconId,
          actorId: actorId,
          relatedBeaconId: relatedBeaconId,
        ),
      ]);
      expect(result, hasLength(1));
      return result.single;
    }

    test(
      'a readable Request resolves with its normalized title',
      () async {
        final id = await one(_r, _readable);
        expect(id.entityKind, NotificationEntityKind.request);
        expect(id.readable, isTrue);
        expect(id.tombstone, isFalse);
        expect(id.expired, isFalse);
        expect(id.label, 'Fix the roof');
      },
      skip: skipReason,
    );

    test(
      'an unreadable Request exposes no title in any string field',
      () async {
        final id = await one(
          _r,
          _unreadable,
          actorId: _a,
          relatedBeaconId: _unreadable,
        );
        expect(id.readable, isFalse);
        expect(id.tombstone, isFalse);
        expect(id.label, isNull);
        expect(id.relatedLabel, isNull);
        expect(id.hasImage, isFalse);
        for (final text in [id.label, id.actorName, id.relatedLabel]) {
          expect(text ?? '', isNot(contains('Secret roof plan')));
        }
      },
      skip: skipReason,
    );

    test(
      'an actor who blocked the recipient is hidden',
      () async {
        final id = await one(_r, _readable, actorId: _blockerA);
        expect(id.actorHidden, isTrue);
        expect(id.actorName, isNull);
      },
      skip: skipReason,
    );

    test(
      'an actor the recipient blocked is hidden',
      () async {
        final id = await one(_blockerR, _readableForBlockerR, actorId: _a);
        expect(id.actorHidden, isTrue);
        expect(id.actorName, isNull);
      },
      skip: skipReason,
    );

    test(
      'an unblocked actor keeps a visible name',
      () async {
        final id = await one(_r, _readable, actorId: _a);
        expect(id.actorHidden, isFalse);
        expect(id.actorName, 'Anna');
      },
      skip: skipReason,
    );

    test(
      'a deleted Request with a readable tombstone is a tombstone',
      () async {
        final id = await one(_r, _deletedSeen);
        expect(id.tombstone, isTrue);
        expect(id.readable, isFalse);
        expect(id.label, isNull);
      },
      skip: skipReason,
    );

    test(
      'a deleted Request without a readable tombstone is not a tombstone',
      () async {
        final id = await one(_r, _deletedUnseen);
        expect(id.tombstone, isFalse);
        expect(id.readable, isFalse);
        expect(id.label, isNull);
      },
      skip: skipReason,
    );

    test(
      'a draft is readable with its title only for its author',
      () async {
        final author = await one(_a, _draft);
        expect(author.readable, isTrue);
        expect(author.label, 'Draft plan');
        final other = await one(_r, _draft);
        expect(other.readable, isFalse);
        expect(other.label, isNull);
      },
      skip: skipReason,
    );

    test(
      'a Post carries its root text capped at 40 graphemes',
      () async {
        final id = await one(_r, _postText);
        expect(id.entityKind, NotificationEntityKind.post);
        expect(id.readable, isTrue);
        expect(id.label, 'Anyone has a ladder for Saturday?');
        expect(id.hasImage, isFalse);
        final long = await one(_r, _postLong);
        expect(long.label, 'Looking for a very long description of…');
      },
      skip: skipReason,
    );

    test(
      'an image-only Post sets the image flag and has no text',
      () async {
        final id = await one(_r, _postImage);
        expect(id.entityKind, NotificationEntityKind.post);
        expect(id.hasImage, isTrue);
        expect(id.label, isNull);
      },
      skip: skipReason,
    );

    test(
      'a Post with an empty root has neither text nor image flag',
      () async {
        final id = await one(_r, _postEmpty);
        expect(id.entityKind, NotificationEntityKind.post);
        expect(id.hasImage, isFalse);
        expect(id.label, isNull);
      },
      skip: skipReason,
    );

    test(
      'an expired Post stays readable and is flagged expired',
      () async {
        final expired = await one(_r, _postExpired);
        expect(expired.readable, isTrue);
        expect(expired.expired, isTrue);
        expect(expired.label, 'Old news');
        final live = await one(_r, _postText);
        expect(live.expired, isFalse);
      },
      skip: skipReason,
    );

    test(
      'an erased actor has no name but is not hidden',
      () async {
        final empty = await one(_r, _readable, actorId: _erased);
        expect(empty.actorName, isNull);
        expect(empty.actorHidden, isFalse);
        final blank = await one(_r, _readable, actorId: _blank);
        expect(blank.actorName, isNull);
        expect(blank.actorHidden, isFalse);
        final missing = await one(_r, _readable, actorId: _missingActor);
        expect(missing.actorName, isNull);
        expect(missing.actorHidden, isFalse);
      },
      skip: skipReason,
    );

    test(
      'an actor name is capped at 32 graphemes',
      () async {
        final id = await one(_r, _readable, actorId: _longName);
        expect(id.actorName, 'Bartholomew Montgomery Feathers…');
      },
      skip: skipReason,
    );

    test(
      'a related Request is labelled only when readable',
      () async {
        final seen = await one(_r, _readable, relatedBeaconId: _readable);
        expect(seen.relatedLabel, 'Fix the roof');
        final hidden = await one(_r, _readable, relatedBeaconId: _unreadable);
        expect(hidden.relatedLabel, isNull);
      },
      skip: skipReason,
    );

    test(
      'a Post the recipient cannot read exposes no text, image flag or expiry',
      () async {
        for (final post in [_postText, _postImage, _postExpired]) {
          final id = await one(_stranger, post);
          expect(id.entityKind, NotificationEntityKind.post, reason: post);
          expect(id.readable, isFalse, reason: post);
          expect(id.label, isNull, reason: post);
          expect(id.hasImage, isFalse, reason: post);
          expect(id.tombstone, isFalse, reason: post);
          expect(id.expired, isFalse, reason: post);
        }
      },
      skip: skipReason,
    );

    test(
      'a mixed batch returns one identity per request in order '
      'with a single SQL statement',
      () async {
        final requests = [
          const IdentityRequest(beaconId: _unreadable),
          const IdentityRequest(beaconId: _readable, actorId: _a),
          const IdentityRequest(beaconId: _deletedSeen),
          const IdentityRequest(beaconId: _postText),
          const IdentityRequest(beaconId: _postImage),
          const IdentityRequest(beaconId: _postExpired),
          const IdentityRequest(beaconId: _draft),
          const IdentityRequest(beaconId: _readable, actorId: _blockerA),
          const IdentityRequest(beaconId: _readable, actorId: _erased),
          const IdentityRequest(beaconId: _readable, relatedBeaconId: _readable),
          const IdentityRequest(beaconId: _deletedUnseen),
          const IdentityRequest(beaconId: _postEmpty),
          const IdentityRequest(beaconId: _readable, actorId: _missingActor),
        ];
        counter.reset();
        final result = await identities.resolve(_r, requests);
        expect(
          counter.count,
          1,
          reason: 'counts every statement incl. BEGIN/COMMIT: exactly one '
              'SELECT and no transaction wrapper',
        );
        expect(result, hasLength(requests.length));
        expect(result[0].readable, isFalse);
        expect(result[1].label, 'Fix the roof');
        expect(result[1].actorName, 'Anna');
        expect(result[2].tombstone, isTrue);
        expect(result[3].entityKind, NotificationEntityKind.post);
        expect(result[4].hasImage, isTrue);
        expect(result[5].expired, isTrue);
        expect(result[6].readable, isFalse);
        expect(result[7].actorHidden, isTrue);
        expect(result[8].actorName, isNull);
        expect(result[9].relatedLabel, 'Fix the roof');
        expect(result[10].tombstone, isFalse);
        expect(result[10].readable, isFalse);
        expect(result[11].entityKind, NotificationEntityKind.post);
        expect(result[11].label, isNull);
        expect(result[11].hasImage, isFalse);
        expect(result[12].actorName, isNull);
        expect(result[12].actorHidden, isFalse);
      },
      skip: skipReason,
    );
  });
}

const _r = 'Unir00recipient';
const _a = 'Unia00actor';
const _blockerA = 'Unib00blockera';
const _blockerR = 'Unib00blockerr';
const _erased = 'Unie00erased';
const _blank = 'Unie00blank';
const _stranger = 'Unis00stranger';
const _longName = 'Unil00longname';
const _readable = 'Bnir00readable';
const _readableForBlockerR = 'Bnir00readblkr';
const _unreadable = 'Bnir00unread';
const _deletedSeen = 'Bnir00delseen';
const _deletedUnseen = 'Bnir00delunseen';
const _draft = 'Bnir00draft';
const _postText = 'Bnir00posttext';
const _postLong = 'Bnir00postlong';
const _postImage = 'Bnir00postimage';
const _postEmpty = 'Bnir00postempty';
const _postExpired = 'Bnir00postexp';
const _longPostBody =
    'Looking for   a very\nlong description of everything we need to build';
const _longActorName = 'Bartholomew Montgomery Featherstonehaugh';
const _missingActor = 'Unim00nouserrow';

Future<void> _user(
  Connection w,
  String id,
  String name,
  int slot,
) => w.execute(
  Sql.named(
    'INSERT INTO public."user" (id, display_name, public_key) '
    'VALUES (@id, @name, @key)',
  ),
  parameters: {'id': id, 'name': name, 'key': pgTestPublicKey('notifident', slot)},
);

Future<void> _request(
  Connection w,
  String id,
  String author,
  String title, {
  int status = 0,
  String? forwardTo,
}) async {
  await w.execute(
    Sql.named(
      'INSERT INTO public.beacon '
      '(id, user_id, title, description, status, is_discoverable) '
      "VALUES (@id, @author, @title, 'd', @status, false)",
    ),
    parameters: {
      'id': id,
      'author': author,
      'title': title,
      'status': status,
    },
  );
  if (forwardTo != null) await _forward(w, id, author, forwardTo);
}

Future<void> _forward(Connection w, String beacon, String from, String to) =>
    w.execute(
      Sql.named(
        'INSERT INTO public.beacon_forward_edge '
        '(beacon_id, sender_id, recipient_id) VALUES (@b, @s, @r)',
      ),
      parameters: {'b': beacon, 's': from, 'r': to},
    );

Future<void> _post(
  Connection w,
  String id,
  String rootBody, {
  int status = 0,
  bool image = false,
}) async {
  await w.execute(
    Sql.named(
      'INSERT INTO public.beacon '
      '(id, user_id, title, description, status, kind, is_discoverable) '
      "VALUES (@id, @a, '', '', @status, 1, false)",
    ),
    parameters: {'id': id, 'a': _a, 'status': status},
  );
  final root = 'Rnir${id.substring(4)}';
  await w.execute(
    Sql.named(
      'INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body) '
      'VALUES (@m, @b, @a, @body)',
    ),
    parameters: {'m': root, 'b': id, 'a': _a, 'body': rootBody},
  );
  await w.execute(
    Sql.named('UPDATE public.beacon SET post_root_message_id = @m WHERE id = @b'),
    parameters: {'m': root, 'b': id},
  );
  if (image) {
    await w.execute(
      Sql.named(
        'INSERT INTO public.beacon_room_message_attachment '
        "(message_id, kind, file_url, mime) VALUES (@m, 1, 'x.png', 'image/png')",
      ),
      parameters: {'m': root},
    );
  }
  await _forward(w, id, _a, _r);
}

Future<void> _seed(Connection w) async {
  await _user(w, _r, 'Rita', 1);
  await _user(w, _a, '  Anna  ', 2);
  await _user(w, _blockerA, 'Blocky', 3);
  await _user(w, _blockerR, 'Blocked-by-me Rita', 4);
  await _user(w, _erased, '', 5);
  await _user(w, _blank, '   ', 6);
  await _user(w, _stranger, 'Stranger', 8);
  await _user(w, _longName, _longActorName, 7);

  await _request(w, _readable, _a, 'Fix  the\nroof', forwardTo: _r);
  await _request(w, _readableForBlockerR, _a, 'Shared one', forwardTo: _blockerR);
  await _request(w, _unreadable, _a, 'Secret roof plan');
  await _request(w, _deletedSeen, _a, 'Gone', status: 2, forwardTo: _r);
  await _request(w, _deletedUnseen, _a, 'Gone too', status: 2);
  await _request(w, _draft, _a, 'Draft plan', status: 3);

  await _post(w, _postText, 'Anyone has a ladder for Saturday?');
  await _post(
    w,
    _postLong,
    _longPostBody,
  );
  await _post(w, _postImage, '', image: true);
  await _post(w, _postEmpty, '');
  // Archiving rejects new room messages, so expire the Post after its root.
  await _post(w, _postExpired, 'Old news');
  await w.execute(
    Sql.named('UPDATE public.beacon SET status = 6 WHERE id = @id'),
    parameters: {'id': _postExpired},
  );

  for (final (blocker, blocked) in const [
    (_blockerA, _r),
    (_blockerR, _a),
  ]) {
    await w.execute(
      Sql.named(
        'INSERT INTO public.user_block (blocker_id, blocked_id, origin_id) '
        'VALUES (@x, @y, @x)',
      ),
      parameters: {'x': blocker, 'y': blocked},
    );
  }
}
