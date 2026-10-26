@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

/// Post lifetime columns on `beacon`: `expires_at`, `expiry_warning_eligible`,
/// the backfill of open Posts, the CHECK that ties `expires_at` to open Posts
/// and the trigger that defaults it to 72 hours after publication.
/// See `docs/plans/post-ttl-implementation-plan.md` unit S1.
const _author = 'Uexpiresatauthor';

const _statusOpen = 0;
const _statusDraft = 3;
const _statusClosed = 6;
const _kindRequest = 0;
const _kindPost = 1;

const _checkViolation = '23514';

// Seeded on the pre-migration schema.
const _postPublished10hAgo = 'Bexpiresatupg01';
const _postPublished100hAgo = 'Bexpiresatupg02';
const _postWithoutPublishedAt = 'Bexpiresatupg03';
const _postDraft = 'Bexpiresatupg04';
const _postClosed = 'Bexpiresatupg05';
const _requestOpen = 'Bexpiresatupg06';
const _requestClosed = 'Bexpiresatupg07';
const _requestDraft = 'Bexpiresatupg08';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_EXPIRES_AT_MIGRATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_expires_at',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('Post expiry columns after upgrading from schema 0260', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: target,
        lastInclusiveVersion: '0260',
      );
      writer = session.writer;
      await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$_author', '$_author', 'pk-$_author')
''');
      await _seedPreMigrationBeacons(writer);

      await migrateDbSchema(writer);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    group('backfill of open Posts', () {
      test('an open Post published 10 hours ago expires 72 hours after '
          'publication', () async {
        final row = (await writer.execute('''
SELECT expires_at = published_at + interval '72 hours'
FROM public.beacon WHERE id = '$_postPublished10hAgo'
''')).single;
        expect(row.single, isTrue);
      });

      test(
        'an open Post published 100 hours ago gets a 24 hour grace '
        'period from the migration instead of an expiry in the past',
        () async {
          final row = (await writer.execute('''
SELECT expires_at BETWEEN now() + interval '23 hours 50 minutes'
                      AND now() + interval '24 hours 10 minutes'
FROM public.beacon WHERE id = '$_postPublished100hAgo'
''')).single;
          expect(row.single, isTrue);
        },
      );

      test(
        'an open Post without published_at falls back to created_at',
        () async {
          final row = (await writer.execute('''
SELECT expires_at = created_at + interval '72 hours'
FROM public.beacon WHERE id = '$_postWithoutPublishedAt'
''')).single;
          expect(row.single, isTrue);
        },
      );

      test(
        'every backfilled open Post is eligible for the expiry warning',
        () async {
          final rows = await writer.execute('''
SELECT id, expiry_warning_eligible FROM public.beacon
WHERE id IN ('$_postPublished10hAgo', '$_postPublished100hAgo',
             '$_postWithoutPublishedAt')
ORDER BY id
''');
          expect(rows, hasLength(3));
          expect(rows.map((r) => r[1]), everyElement(isTrue));
        },
      );

      test('draft Posts, closed Posts and every Request keep a NULL '
          'expires_at and are not eligible', () async {
        final rows = await writer.execute('''
SELECT id, expires_at, expiry_warning_eligible FROM public.beacon
WHERE id IN ('$_postDraft', '$_postClosed', '$_requestOpen',
             '$_requestClosed', '$_requestDraft')
ORDER BY id
''');
        expect(rows, hasLength(5));
        for (final r in rows) {
          expect(r[1], isNull, reason: 'expires_at of ${r[0]}');
          expect(r[2], isFalse, reason: 'expiry_warning_eligible of ${r[0]}');
        }
      });
    });

    group('defaulting trigger', () {
      tearDown(() async {
        await writer.execute(
          "DELETE FROM public.beacon WHERE id LIKE 'Bexpiresatdef%'",
        );
      });

      test('an open Post inserted without expires_at expires 72 hours after '
          'its published_at', () async {
        await _insertPost(
          writer,
          'Bexpiresatdef01',
          status: _statusOpen,
          publishedAt: "now() - interval '5 hours'",
        );

        final row = (await writer.execute('''
SELECT expires_at = published_at + interval '72 hours', expiry_warning_eligible
FROM public.beacon WHERE id = 'Bexpiresatdef01'
''')).single;
        expect(row[0], isTrue);
        expect(row[1], isTrue);
      });

      test('an open Post inserted without published_at or expires_at expires '
          '72 hours from now', () async {
        await _insertPost(writer, 'Bexpiresatdef02', status: _statusOpen);

        final row = (await writer.execute('''
SELECT expires_at BETWEEN now() + interval '71 hours 50 minutes'
                      AND now() + interval '72 hours 10 minutes',
       expiry_warning_eligible
FROM public.beacon WHERE id = 'Bexpiresatdef02'
''')).single;
        expect(row[0], isTrue);
        expect(row[1], isTrue);
      });

      test('a draft Post updated to open gets the default expiry', () async {
        await _insertPost(
          writer,
          'Bexpiresatdef03',
          status: _statusDraft,
          publishedAt: "now() - interval '2 hours'",
        );
        final draft = (await writer.execute('''
SELECT expires_at, expiry_warning_eligible
FROM public.beacon WHERE id = 'Bexpiresatdef03'
''')).single;
        expect(draft[0], isNull);
        expect(draft[1], isFalse);

        await writer.execute(
          'UPDATE public.beacon SET status = $_statusOpen '
          "WHERE id = 'Bexpiresatdef03'",
        );

        final row = (await writer.execute('''
SELECT expires_at = published_at + interval '72 hours', expiry_warning_eligible
FROM public.beacon WHERE id = 'Bexpiresatdef03'
''')).single;
        expect(row[0], isTrue);
        expect(row[1], isTrue);
      });

      test('an explicit expires_at is kept', () async {
        await _insertPost(
          writer,
          'Bexpiresatdef04',
          status: _statusOpen,
          publishedAt: "now() - interval '1 hour'",
          expiresAt: "'2031-01-01T00:00:00Z'",
        );

        final row = (await writer.execute('''
SELECT expires_at FROM public.beacon WHERE id = 'Bexpiresatdef04'
''')).single;
        expect(row.single, DateTime.utc(2031));
      });
    });

    group('defaulting trigger on publish', () {
      tearDown(() async {
        await writer.execute(
          "DELETE FROM public.beacon WHERE id LIKE 'Bexpiresatupd%'",
        );
      });

      test('a draft Post with an explicit expires_at keeps it when updated '
          'to open', () async {
        await _insertPost(
          writer,
          'Bexpiresatupd01',
          status: _statusDraft,
          publishedAt: "now() - interval '2 hours'",
          expiresAt: "'2031-01-01T00:00:00Z'",
        );

        await writer.execute(
          'UPDATE public.beacon SET status = $_statusOpen '
          "WHERE id = 'Bexpiresatupd01'",
        );

        final row = (await writer.execute('''
SELECT expires_at FROM public.beacon WHERE id = 'Bexpiresatupd01'
''')).single;
        expect(row.single, DateTime.utc(2031));
      });

      test('a draft Post without published_at updated to open expires 72 '
          'hours from now and is eligible for the expiry warning', () async {
        await _insertPost(writer, 'Bexpiresatupd02', status: _statusDraft);

        await writer.execute(
          'UPDATE public.beacon SET status = $_statusOpen '
          "WHERE id = 'Bexpiresatupd02'",
        );

        final row = (await writer.execute('''
SELECT expires_at BETWEEN now() + interval '71 hours 50 minutes'
                      AND now() + interval '72 hours 10 minutes',
       expiry_warning_eligible
FROM public.beacon WHERE id = 'Bexpiresatupd02'
''')).single;
        expect(row[0], isTrue);
        expect(row[1], isTrue);
      });
    });

    group('expires_at CHECK', () {
      tearDown(() async {
        await writer.execute(
          "DELETE FROM public.beacon WHERE id LIKE 'Bexpiresatck%'",
        );
      });

      test('a Request with an expires_at is rejected', () async {
        await expectLater(
          writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, expires_at)
VALUES ('Bexpiresatck01', '$_author', 'Request', 'd', $_statusOpen,
        $_kindRequest, now() + interval '1 hour')
'''),
          throwsA(
            isA<ServerException>()
                .having((e) => e.code, 'sqlstate', _checkViolation)
                .having(
                  (e) => e.constraintName,
                  'constraint',
                  'beacon_post_expires_at_ck',
                ),
          ),
        );
      });

      test('a draft Post with an expires_at is accepted', () async {
        await _insertPost(
          writer,
          'Bexpiresatck02',
          status: _statusDraft,
          expiresAt: "now() + interval '1 hour'",
        );

        final row = (await writer.execute('''
SELECT expires_at IS NOT NULL FROM public.beacon WHERE id = 'Bexpiresatck02'
''')).single;
        expect(row.single, isTrue);
      });
    });
  });
}

Future<void> _seedPreMigrationBeacons(Connection writer) async {
  await _insertBeacon(
    writer,
    _postPublished10hAgo,
    kind: _kindPost,
    status: _statusOpen,
    publishedAt: "now() - interval '10 hours'",
  );
  await _insertBeacon(
    writer,
    _postPublished100hAgo,
    kind: _kindPost,
    status: _statusOpen,
    publishedAt: "now() - interval '100 hours'",
  );
  await _insertBeacon(
    writer,
    _postWithoutPublishedAt,
    kind: _kindPost,
    status: _statusOpen,
    createdAt: "now() - interval '20 hours'",
  );
  await _insertBeacon(
    writer,
    _postDraft,
    kind: _kindPost,
    status: _statusDraft,
  );
  await _insertBeacon(
    writer,
    _postClosed,
    kind: _kindPost,
    status: _statusClosed,
    publishedAt: "now() - interval '10 hours'",
  );
  await _insertBeacon(
    writer,
    _requestOpen,
    kind: _kindRequest,
    status: _statusOpen,
    publishedAt: "now() - interval '10 hours'",
  );
  await _insertBeacon(
    writer,
    _requestClosed,
    kind: _kindRequest,
    status: _statusClosed,
    publishedAt: "now() - interval '10 hours'",
  );
  await _insertBeacon(
    writer,
    _requestDraft,
    kind: _kindRequest,
    status: _statusDraft,
  );
}

Future<void> _insertBeacon(
  Connection writer,
  String id, {
  required int kind,
  required int status,
  String? publishedAt,
  String? createdAt,
}) => writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   published_at, created_at)
VALUES ('$id', '$_author', '', '', $status, $kind, false,
        ${publishedAt ?? 'NULL'}, ${createdAt ?? 'now()'})
''');

/// Inserts a Post on the migrated schema; [expiresAt] is a SQL expression.
Future<void> _insertPost(
  Connection writer,
  String id, {
  required int status,
  String? publishedAt,
  String? expiresAt,
}) => writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   published_at${expiresAt == null ? '' : ', expires_at'})
VALUES ('$id', '$_author', '', '', $status, $_kindPost, false,
        ${publishedAt ?? 'NULL'}${expiresAt == null ? '' : ', $expiresAt'})
''');
