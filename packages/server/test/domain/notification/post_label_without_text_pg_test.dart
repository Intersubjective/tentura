@Tags(['pg'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/notification_identity_repository.dart';
import 'package:tentura_server/domain/notification/notification_copy_renderer.dart';
import 'package:tentura_server/domain/notification/notification_identity.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

// A Post with neither text nor image is named after its author, the same
// words the client shows («Post · Alice»), in the push title, the email
// subject and the digest heading. The identity is read from Postgres.

const _recipient = 'Upostlabel0001';
const _author = 'Upostlabel0002';
const _post = 'Bpostlabel0001';
const _root = 'Rpostlabel0001';
final _now = DateTime.utc(2026, 11, 16, 9);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_LABEL_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_label',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('label of a Post without text or image', () {
    late DisposablePgWriterSession session;
    late TenturaDb db;
    late NotificationIdentityPort identities;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: target);
        db = openDisposablePgDatabase(target);
        identities = NotificationIdentityRepository(db);
        await _seed(session.writer);
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session, drift: db);
      });
    }

    Future<NotificationCopy> copy(
      String locale, {
      String key = 'relay_received',
    }) async {
      final identity = (await identities.resolve(_recipient, [
        const IdentityRequest(beaconId: _post),
      ])).single;
      return const NotificationCopyRenderer().render(
        presentationKey: key,
        kind: null,
        facts: {
          'beaconKind': 'post',
          if (key == 'post_expiring_soon')
            'expiresAt': _now.add(const Duration(hours: 2)).toIso8601String(),
        },
        identity: identity,
        locale: locale,
        tzOffsetMinutes: 0,
        now: _now,
      );
    }

    test(
      'is «Post · {author}» in English',
      () async {
        final rendered = await copy('en');
        expect(rendered.entityLabel, 'Post · Alice');
        expect(
          const NotificationCopyRenderer().emailSubject(
            rendered,
            quoteLabel: false,
          ),
          contains('Post · Alice'),
        );
      },
      skip: skipReason,
    );

    test(
      'is «Пост · {author}» in Russian',
      () async {
        final rendered = await copy('ru');
        expect(rendered.entityLabel, 'Пост · Alice');
        expect(
          const NotificationCopyRenderer().emailSubject(
            rendered,
            quoteLabel: false,
          ),
          contains('Пост · Alice'),
        );
      },
      skip: skipReason,
    );

    for (final key in const [
      'post_first_response',
      'post_expiring_soon',
      'room_message_posted',
    ]) {
      test(
        '$key names the Post «Post · {author}» / «Пост · {author}»',
        () async {
          expect((await copy('en', key: key)).entityLabel, 'Post · Alice');
          expect((await copy('ru', key: key)).entityLabel, 'Пост · Alice');
        },
        skip: skipReason,
      );
    }

    // The client words come from its ARB files; the server must say the same.
    for (final locale in const ['en', 'ru']) {
      test(
        '$locale label equals the client `updatesPostLabelByAuthor` text',
        () async {
          final arb =
              jsonDecode(
                    File('../client/l10n/app_$locale.arb').readAsStringSync(),
                  )
                  as Map<String, dynamic>;
          final clientLabel = (arb['updatesPostLabelByAuthor']! as String)
              .replaceAll('{author}', 'Alice');
          expect((await copy(locale)).entityLabel, clientLabel);
        },
        skip: skipReason,
      );
    }
  });
}

Future<void> _seed(Connection w) async {
  for (final (id, name, slot) in const [
    (_recipient, 'Rita', 1),
    (_author, 'Alice', 2),
  ]) {
    await w.execute(
      Sql.named(
        'INSERT INTO public."user" (id, display_name, public_key) '
        'VALUES (@id, @name, @key)',
      ),
      parameters: {
        'id': id,
        'name': name,
        'key': pgTestPublicKey('postlabel', slot),
      },
    );
  }
  await w.execute(
    Sql.named(
      'INSERT INTO public.beacon '
      '(id, user_id, title, description, status, kind, is_discoverable) '
      "VALUES (@id, @a, '', '', 0, 1, false)",
    ),
    parameters: {'id': _post, 'a': _author},
  );
  await w.execute(
    Sql.named(
      'INSERT INTO public.beacon_room_message (id, beacon_id, author_id, body) '
      "VALUES (@m, @b, @a, '')",
    ),
    parameters: {'m': _root, 'b': _post, 'a': _author},
  );
  await w.execute(
    Sql.named(
      'UPDATE public.beacon SET post_root_message_id = @m WHERE id = @b',
    ),
    parameters: {'m': _root, 'b': _post},
  );
  await w.execute(
    Sql.named(
      'INSERT INTO public.beacon_forward_edge '
      '(beacon_id, sender_id, recipient_id) VALUES (@b, @s, @r)',
    ),
    parameters: {'b': _post, 's': _author, 'r': _recipient},
  );
}
