@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// `public.beacon_fact_access(beacon_id, user_id)` is the one access rule for
/// facts: who may read them (`can_read`) and who may write them and see their
/// history (`can_use_room`), plus the beacon facts every caller needs
/// (`kind`, `status`, `is_draft`, `is_expired_post`).
///
/// The rule is stricter than the room policy: blocks apply on Requests as
/// well as Posts, a deleted beacon is closed to everyone, and a draft belongs
/// to its author alone.

/// The last migration that had shipped before the fact access rule. The
/// function must come from a migration after it: a shipped migration is never
/// edited.
const _lastShippedVersion = 310;

const _author = 'Ufaccauthor0';
const _steward = 'Ufaccsteward';
const _member = 'Ufaccmember0';
const _leaver = 'Ufaccleaver0';
const _stranger = 'Ufaccstrange';
const _requested = 'Ufaccrequest';
const _invited = 'Ufaccinvited';
const _muted = 'Ufaccmuted00';
const _blockedRequestMember = 'Ufaccblkreq0';
const _blockedPostMember = 'Ufaccblkpost';

const _openRequest = 'Bfaccopenreq';
const _draftRequest = 'Bfaccdraftrq';
const _deletedRequest = 'Bfaccdeleted';
const _openPost = 'Bfaccopenpst';
const _openPostRoot = 'Rfaccopenpst';
const _rootlessOpenPost = 'Bfaccnoroot0';
const _rootlessClosedPost = 'Bfaccclosed0';
const _expiredOpenPost = 'Bfaccexpired';
const _expiredClosedPost = 'Bfaccexpclsd';

const _columns = [
  'beacon_exists',
  'kind',
  'status',
  'is_draft',
  'is_expired_post',
  'can_read',
  'can_use_room',
];

Future<void> main() async {
  final defining = migrationsForTesting
      .where(
        (migration) => migration.statements.any(
          (statement) => RegExp(
            r'CREATE\s+(OR\s+REPLACE\s+)?FUNCTION\s+'
            r'(public\.)?beacon_fact_access\s*\(',
            caseSensitive: false,
          ).hasMatch(statement),
        ),
      )
      .toList();

  test(
    'the function comes from a new registered migration after every shipped '
    'one, never from an edited shipped migration',
    () {
      expect(
        defining,
        isNotEmpty,
        reason: 'a registered migration creates public.beacon_fact_access',
      );
      for (final migration in defining) {
        expect(
          int.parse(migration.version),
          greaterThan(_lastShippedVersion),
          reason:
              'migration ${migration.version} defines beacon_fact_access; '
              'shipped migrations stay as shipped',
        );
      }
    },
  );

  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BEACON_FACT_ACCESS_TEST_DB',
    defaultNamePrefix: 'tentura_test_beacon_fact_access',
  );
  final skip = await pgSkipReason(target);
  if (skip != null) {
    test('Postgres unavailable', () {}, skip: skip);
    return;
  }

  late DisposablePgWriterSession session;
  late Connection writer;
  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
    writer = session.writer;
    await _seed(writer);
  });
  tearDownAll(() => tearDownDisposablePgWriter(session: session));

  Future<Map<String, dynamic>> access(String beaconId, String userId) async {
    final rows = await writer.execute(
      Sql.named(
        'SELECT * FROM public.beacon_fact_access(@beacon_id, @user_id)',
      ),
      parameters: {'beacon_id': beaconId, 'user_id': userId},
    );
    expect(rows, hasLength(1), reason: 'one row for $beaconId / $userId');
    return rows.single.toColumnMap();
  }

  Future<bool> canUseRoom(String beaconId, String userId) async =>
      (await access(beaconId, userId))['can_use_room'] as bool;

  group('beacon_fact_access shape', () {
    test(
      'the migrated schema exposes the function with its seven columns',
      () async {
        final rows = await writer.execute(
          "SELECT to_regprocedure('public.beacon_fact_access(text, text)') "
          'IS NOT NULL',
        );
        expect(rows.single.single, isTrue);
        final row = await access(_openRequest, _author);
        expect(row.keys.toSet(), _columns.toSet());
        expect(row, hasLength(_columns.length));
      },
    );

    test(
      'an existing beacon gives exactly one row with beacon_exists true',
      () async {
        expect(
          (await access(_openRequest, _stranger))['beacon_exists'],
          isTrue,
        );
      },
    );

    test('an unknown beacon id still gives one row, with no access', () async {
      final row = await access('Bfaccmissing', _author);
      expect(row['beacon_exists'], isFalse);
      expect(row['can_read'], isFalse);
      expect(row['can_use_room'], isFalse);
    });

    test('kind and status are reported exactly as stored', () async {
      final request = await access(_openRequest, _author);
      expect([request['kind'], request['status']], [0, 0]);
      final closedPost = await access(_rootlessClosedPost, _author);
      expect([closedPost['kind'], closedPost['status']], [1, 6]);
    });
  });

  group('can_use_room on an open Request', () {
    test('author, steward and admitted participant may use the room', () async {
      for (final user in [_author, _steward, _member]) {
        final row = await access(_openRequest, user);
        expect(row['can_read'], isTrue, reason: user);
        expect(row['can_use_room'], isTrue, reason: user);
      }
    });

    test('a leaver who can still read may not use the room', () async {
      final row = await access(_openRequest, _leaver);
      expect(row['can_read'], isTrue);
      expect(row['can_use_room'], isFalse);
    });

    test('a stranger may neither read nor use the room', () async {
      final row = await access(_openRequest, _stranger);
      expect(row['can_read'], isFalse);
      expect(row['can_use_room'], isFalse);
    });

    test('only admitted room access counts: requested, invited and muted '
        'participants are kept out of the room', () async {
      for (final user in [_requested, _invited, _muted]) {
        final row = await access(_openRequest, user);
        expect(row['can_use_room'], isFalse, reason: user);
      }
      expect(await canUseRoom(_openRequest, _member), isTrue);
    });

    test('an admitted participant in a block pair with the author loses both '
        'reading and the room', () async {
      final row = await access(_openRequest, _blockedRequestMember);
      expect(row['can_read'], isFalse);
      expect(row['can_use_room'], isFalse);
    });

    test(
      'can_read agrees with beacon_can_read_content for the same pair',
      () async {
        for (final user in [_author, _member, _stranger]) {
          final expected = await writer.execute(
            Sql.named(
              'SELECT public.beacon_can_read_content(@beacon_id, @user_id)',
            ),
            parameters: {'beacon_id': _openRequest, 'user_id': user},
          );
          expect(
            (await access(_openRequest, user))['can_read'],
            expected.single.single,
            reason: user,
          );
        }
      },
    );
  });

  group('can_use_room on Posts, deleted beacons and drafts', () {
    test('a blocked Post member may neither read nor use the room', () async {
      final row = await access(_openPost, _blockedPostMember);
      expect(row['can_read'], isFalse);
      expect(row['can_use_room'], isFalse);
      expect(await canUseRoom(_openPost, _member), isTrue);
    });

    test(
      'a deleted beacon is closed to everyone, the author included',
      () async {
        for (final user in [_author, _steward, _member, _stranger]) {
          final row = await access(_deletedRequest, user);
          expect(row['beacon_exists'], isTrue, reason: user);
          expect(row['can_read'], isFalse, reason: user);
          expect(row['can_use_room'], isFalse, reason: user);
        }
      },
    );

    test('a draft is open to its author only and reports is_draft', () async {
      final authorRow = await access(_draftRequest, _author);
      expect(authorRow['is_draft'], isTrue);
      expect(authorRow['can_read'], isTrue);
      expect(authorRow['can_use_room'], isTrue);
      for (final user in [_steward, _member, _stranger]) {
        final row = await access(_draftRequest, user);
        expect(row['is_draft'], isTrue, reason: user);
        expect(row['can_read'], isFalse, reason: user);
        expect(row['can_use_room'], isFalse, reason: user);
      }
    });
  });

  group('is_draft', () {
    test('an open Post without a root message is still a draft', () async {
      expect((await access(_rootlessOpenPost, _author))['is_draft'], isTrue);
    });

    test('a closed Post without a root message is not a draft', () async {
      expect(
        (await access(_rootlessClosedPost, _author))['is_draft'],
        isFalse,
      );
    });

    test('an open Post with a root message and an open Request are not '
        'drafts', () async {
      expect((await access(_openPost, _author))['is_draft'], isFalse);
      expect((await access(_openRequest, _author))['is_draft'], isFalse);
    });
  });

  group('is_expired_post', () {
    test('an open Post past its expiry is an expired Post', () async {
      expect(
        (await access(_expiredOpenPost, _author))['is_expired_post'],
        isTrue,
      );
    });

    test('an open Post whose expiry is in the future is not expired', () async {
      final expiry = await writer.execute(
        "SELECT expires_at > now() FROM public.beacon WHERE id = '$_openPost'",
      );
      expect(expiry.single.single, isTrue, reason: 'fixture: future expiry');
      expect((await access(_openPost, _author))['is_expired_post'], isFalse);
    });

    test(
      'a closed Post past its expiry and a Request are not expired Posts',
      () async {
        expect(
          (await access(_expiredClosedPost, _author))['is_expired_post'],
          isFalse,
        );
        expect(
          (await access(_openRequest, _author))['is_expired_post'],
          isFalse,
        );
      },
    );
  });
}

Future<void> _seed(Connection writer) async {
  await writer.execute('TRUNCATE public."user" CASCADE');
  const users = [
    _author,
    _steward,
    _member,
    _leaver,
    _stranger,
    _requested,
    _invited,
    _muted,
    _blockedRequestMember,
    _blockedPostMember,
  ];
  for (final (index, id) in users.indexed) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {
        'id': id,
        'key': pgTestPublicKey(
          index < 9 ? 'faccess' : 'gaccess',
          index % 9 + 1,
        ),
      },
    );
  }

  // Requests.
  await writer.execute('''
INSERT INTO public.beacon (id, user_id, title, description, status, kind, published_at)
VALUES ('$_openRequest', '$_author', 'Open', '', 0, 0, now()),
       ('$_deletedRequest', '$_author', 'Deleted', '', 0, 0, now()),
       ('$_draftRequest', '$_author', 'Draft', '', 3, 0, NULL)
''');
  await writer.execute(
    "UPDATE public.beacon SET status = 2 WHERE id = '$_deletedRequest'",
  );

  // Posts. Every Post is inserted open with an explicit expiry (an open Post
  // must carry one), then given its lifecycle.
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, forward_policy,
   is_discoverable, published_at, expires_at)
VALUES ('$_openPost', '$_author', '', '', 0, 1, 1, false, now(),
        now() + interval '24 hours'),
       ('$_rootlessOpenPost', '$_author', '', '', 0, 1, 1, false, now(),
        now() + interval '24 hours'),
       ('$_rootlessClosedPost', '$_author', '', '', 0, 1, 1, false, now(),
        now() + interval '24 hours'),
       ('$_expiredOpenPost', '$_author', '', '', 0, 1, 1, false,
        now() - interval '73 hours', now() - interval '1 hour'),
       ('$_expiredClosedPost', '$_author', '', '', 0, 1, 1, false,
        now() - interval '73 hours', now() - interval '1 hour')
''');
  await writer.execute('''
INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body)
VALUES ('$_openPostRoot', '$_openPost', '$_author', 'Root')
''');
  await writer.execute('''
UPDATE public.beacon SET post_root_message_id = '$_openPostRoot'
WHERE id = '$_openPost'
''');
  for (final id in [_rootlessClosedPost, _expiredClosedPost]) {
    await writer.execute(
      "UPDATE public.beacon SET status = 6 WHERE id = '$id'",
    );
  }

  // Stewards on the open, deleted and draft Requests.
  await writer.execute('''
INSERT INTO public.beacon_steward (beacon_id, user_id)
VALUES ('$_openRequest', '$_steward'),
       ('$_deletedRequest', '$_steward'),
       ('$_draftRequest', '$_steward')
''');

  // Participants. role 0 so only room_access (and forward edges) decide.
  final participants = <(String, String, int)>[
    (_openRequest, _member, 3),
    (_openRequest, _leaver, 5),
    (_openRequest, _requested, 1),
    (_openRequest, _invited, 2),
    (_openRequest, _muted, 4),
    (_openRequest, _blockedRequestMember, 3),
    (_deletedRequest, _member, 3),
    (_draftRequest, _member, 3),
    (_openPost, _member, 3),
    (_openPost, _blockedPostMember, 3),
  ];
  for (final (index, (beaconId, userId, roomAccess)) in participants.indexed) {
    await writer.execute('''
INSERT INTO public.beacon_participant (id, beacon_id, user_id, role, status, room_access)
VALUES ('Pfacc$index', '$beaconId', '$userId', 0, 0, $roomAccess)
''');
  }

  // Forward edges keep the non-admitted participants readable, so their
  // can_use_room false comes from room_access, not from can_read.
  for (final (index, userId) in [
    _leaver,
    _requested,
    _invited,
    _muted,
  ].indexed) {
    await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('Ffacc$index', '$_openRequest', '$_author', '$userId')
''');
  }

  // Block pairs with the author, one per direction.
  await writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$_author', '$_blockedRequestMember', '$_blockedRequestMember'),
       ('$_blockedPostMember', '$_author', '$_author')
''');
}
