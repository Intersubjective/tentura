@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

/// m0209: Post columns on `beacon` (kind, forward policy, last activity, root
/// message), their CHECKs, the one-way guard trigger, the last-activity bump
/// triggers and `beacon_pinned.pinned_at`.
/// See `docs/plans/post-and-constellation-composer-plan.md` §4.1.
const _author = 'Um0209author01';
const _other = 'Um0209other001';

const _statusOpen = 0;
const _statusDeleted = 2;
const _statusDraft = 3;
const _statusClosed = 6;

const _checkViolation = '23514';

const _t2029 = '2029-01-01T00:00:00Z';
const _t2030 = '2030-01-01T00:00:00Z';
const _t2031 = '2031-01-01T00:00:00Z';
const _t2032 = '2032-01-01T00:00:00Z';
const _t2033 = '2033-01-01T00:00:00Z';

Future<void> main() async {
  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0209_POST_SCHEMA_MIGRATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0209_post_mig',
  );
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0209_POST_SCHEMA_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0209_post',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('upgrade from the previous schema version', () {
    late DisposablePgWriterSession session;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(
        target: migrationTarget,
        lastInclusiveVersion: '0208',
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    test(
      'backfills last activity from the newest non-system message, then '
      'publication time, then creation time',
      () async {
        final writer = session.writer;
        await _insertUser(writer, _author);
        await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, created_at, published_at)
VALUES
  ('Bm0209upg0001', '$_author', 'With messages', 'd', 0,
   '2020-01-01T00:00:00Z', '2020-01-02T00:00:00Z'),
  ('Bm0209upg0002', '$_author', 'Published only', 'd', 0,
   '2020-02-01T00:00:00Z', '2020-02-02T00:00:00Z'),
  ('Bm0209upg0003', '$_author', 'Draft', 'd', 3,
   '2020-03-01T00:00:00Z', NULL)
''');
        await writer.execute('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, created_at, system_message_kind)
VALUES
  ('Rm0209upg001', 'Bm0209upg0001', '$_author', 'older', '2020-05-01T00:00:00Z', NULL),
  ('Rm0209upg002', 'Bm0209upg0001', '$_author', 'newest', '2020-06-01T00:00:00Z', NULL),
  ('Rm0209upg003', 'Bm0209upg0001', NULL, 'notice', '2020-07-01T00:00:00Z', 1)
''');

        await migrateDbSchema(writer);

        final rows = await writer.execute('''
SELECT id, last_activity_at FROM public.beacon
WHERE id LIKE 'Bm0209upg%' ORDER BY id
''');
        expect(
          {for (final r in rows) r[0]! as String: r[1]},
          {
            'Bm0209upg0001': DateTime.utc(2020, 6),
            'Bm0209upg0002': DateTime.utc(2020, 2, 2),
            'Bm0209upg0003': DateTime.utc(2020, 3),
          },
        );
      },
    );

    test(
      'existing beacons keep request kind and open forward policy',
      () async {
        final rows = await session.writer.execute('''
SELECT kind, forward_policy FROM public.beacon WHERE id = 'Bm0209upg0001'
''');
        expect(rows.single[0], 0);
        expect(rows.single[1], 1);
      },
    );
  });

  group('full schema', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      await _insertUser(writer, _author);
      await _insertUser(writer, _other);
    });

    tearDown(() async {
      await writer.execute(
        "DELETE FROM public.beacon_pinned WHERE beacon_id LIKE 'Bm0209%'",
      );
      await writer.execute(
        'DELETE FROM public.beacon_forward_edge '
        "WHERE beacon_id LIKE 'Bm0209%'",
      );
      await writer.execute(
        'DELETE FROM public.beacon_room_message_reaction '
        "WHERE message_id LIKE 'Rm0209%'",
      );
      await writer.execute(
        "DELETE FROM public.beacon_room_message WHERE beacon_id LIKE 'Bm0209%'",
      );
      await writer.execute("DELETE FROM public.beacon WHERE id LIKE 'Bm0209%'");
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    group('columns and defaults', () {
      test('a beacon inserted without the new columns is an open-policy '
          'request', () async {
        await _insertBeacon(writer, 'Bm0209def0001');

        final row = (await writer.execute('''
SELECT kind, forward_policy, last_activity_at, post_root_message_id
FROM public.beacon WHERE id = 'Bm0209def0001'
''')).single;
        expect(row[0], 0);
        expect(row[1], 1);
        expect(row[2], isNull);
        expect(row[3], isNull);
      });

      test('the registry ends at the post-schema migration or later', () {
        expect(
          migrationsForTesting.map((m) => m.version),
          contains('0209'),
        );
      });
    });

    group('kind and forward policy constraints', () {
      test('an empty post draft is accepted', () async {
        await _insertPost(writer, 'Bm0209ck00001');

        final row = (await writer.execute(
          'SELECT kind, forward_policy FROM public.beacon '
          "WHERE id = 'Bm0209ck00001'",
        )).single;
        expect(row[0], 1);
        expect(row[1], 1);
      });

      test('a post with a title is rejected', () async {
        await expectLater(
          _insertPost(writer, 'Bm0209ck00002', title: 'Not allowed'),
          _throwsCheckViolation,
        );
      });

      test('a post with a description is rejected', () async {
        await expectLater(
          _insertPost(writer, 'Bm0209ck00003', description: 'Not allowed'),
          _throwsCheckViolation,
        );
      });

      test('a discoverable post is rejected', () async {
        await expectLater(
          _insertPost(writer, 'Bm0209ck00004', isDiscoverable: true),
          _throwsCheckViolation,
        );
      });

      test('a post with a schedule is rejected', () async {
        await expectLater(
          _insertPost(
            writer,
            'Bm0209ck00005',
            extraColumns: ', start_at',
            extraValues: ", '2030-01-01T00:00:00Z'",
          ),
          _throwsCheckViolation,
        );
      });

      test('a post with an end date is rejected', () async {
        await expectLater(
          _insertPost(
            writer,
            'Bm0209ck00012',
            extraColumns: ', end_at',
            extraValues: ", '2030-01-01T00:00:00Z'",
          ),
          _throwsCheckViolation,
        );
      });

      test('a post nested under a published request is rejected', () async {
        await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at)
VALUES ('Bm0209ck00013', '$_author', 'Parent request', 'd', $_statusOpen, now())
''');

        await expectLater(
          _insertPost(
            writer,
            'Bm0209ck00014',
            extraColumns: ', parent_beacon_id',
            extraValues: ", 'Bm0209ck00013'",
          ),
          _throwsCheckViolation,
        );
      });

      test('a post with a cover image is rejected', () async {
        await expectLater(
          _insertPost(
            writer,
            'Bm0209ck00015',
            extraColumns: ', cover_image_id',
            extraValues: ", '00000000-0000-4000-8000-000000000209'",
          ),
          _throwsCheckViolation,
        );
      });

      test('a post is rejected in every status outside open, deleted and '
          'draft', () async {
        const statuses = {1: 'cancelled', 5: 'review', 7: 'more', 8: 'enough'};
        for (final entry in statuses.entries) {
          await expectLater(
            _insertPost(
              writer,
              'Bm0209ck0002${entry.key}',
              status: entry.key,
            ),
            _throwsCheckViolation,
            reason: 'status ${entry.key} (${entry.value})',
          );
        }
      });

      test('a post in a closed status is rejected', () async {
        await expectLater(
          _insertPost(writer, 'Bm0209ck00006', status: _statusClosed),
          _throwsCheckViolation,
        );
      });

      test('a post may be open, draft or deleted', () async {
        await _insertPost(writer, 'Bm0209ck00007', status: _statusOpen);
        await _insertPost(writer, 'Bm0209ck00008', status: _statusDeleted);

        final rows = await writer.execute(
          'SELECT count(*)::int FROM public.beacon '
          "WHERE id IN ('Bm0209ck00007', 'Bm0209ck00008')",
        );
        expect(rows.single.single, 2);
      });

      test('a request with a closed forward policy is rejected', () async {
        await expectLater(
          _insertBeacon(
            writer,
            'Bm0209ck00009',
            extra: 'forward_policy',
            extraValue: '0',
          ),
          _throwsCheckViolation,
        );
      });

      test('a kind outside request and post is rejected', () async {
        await expectLater(
          _insertBeacon(
            writer,
            'Bm0209ck00010',
            extra: 'kind',
            extraValue: '2',
          ),
          _throwsCheckViolation,
        );
      });

      test('a forward policy outside closed and open is rejected', () async {
        await expectLater(
          _insertPost(
            writer,
            'Bm0209ck00011',
            extraColumns: ', forward_policy',
            extraValues: ', 2',
            includePolicy: false,
          ),
          _throwsCheckViolation,
        );
      });
    });

    group('kind and forward policy guard trigger', () {
      test('a request cannot become a post', () async {
        await _insertBeacon(writer, 'Bm0209gd00001');

        await expectLater(
          writer.execute(
            "UPDATE public.beacon SET kind = 1 WHERE id = 'Bm0209gd00001'",
          ),
          _throwsCheckViolation,
        );
      });

      test('a post draft may close its forward policy', () async {
        await _insertPost(writer, 'Bm0209gd00002');

        await writer.execute(
          'UPDATE public.beacon SET forward_policy = 0 '
          "WHERE id = 'Bm0209gd00002'",
        );

        final rows = await writer.execute(
          'SELECT forward_policy FROM public.beacon '
          "WHERE id = 'Bm0209gd00002'",
        );
        expect(rows.single.single, 0);
      });

      test('a published post cannot close its forward policy', () async {
        await _insertPost(writer, 'Bm0209gd00003', status: _statusOpen);

        await expectLater(
          writer.execute(
            'UPDATE public.beacon SET forward_policy = 0 '
            "WHERE id = 'Bm0209gd00003'",
          ),
          _throwsCheckViolation,
        );
      });

      test('a published post may reopen a closed forward policy', () async {
        await _insertPost(
          writer,
          'Bm0209gd00004',
          status: _statusOpen,
          policy: 0,
        );

        await writer.execute(
          'UPDATE public.beacon SET forward_policy = 1 '
          "WHERE id = 'Bm0209gd00004'",
        );

        final rows = await writer.execute(
          'SELECT forward_policy FROM public.beacon '
          "WHERE id = 'Bm0209gd00004'",
        );
        expect(rows.single.single, 1);
      });
    });

    group('last activity bumps', () {
      test('a non-system message sets last activity to its time', () async {
        await _insertPost(writer, 'Bm0209ac00001');

        await _insertMessage(writer, 'Rm0209ac0001', 'Bm0209ac00001', _t2030);

        expect(
          await _lastActivity(writer, 'Bm0209ac00001'),
          DateTime.utc(2030),
        );
      });

      test('a system message does not bump last activity', () async {
        await _insertPost(writer, 'Bm0209ac00002');

        await _insertMessage(
          writer,
          'Rm0209ac0002',
          'Bm0209ac00002',
          _t2031,
          systemKind: 1,
        );

        expect(await _lastActivity(writer, 'Bm0209ac00002'), isNull);
      });

      test('an older timestamp never lowers last activity', () async {
        await _insertPost(writer, 'Bm0209ac00003');
        await _insertMessage(writer, 'Rm0209ac0003', 'Bm0209ac00003', _t2030);

        await _insertMessage(writer, 'Rm0209ac0004', 'Bm0209ac00003', _t2029);

        expect(
          await _lastActivity(writer, 'Bm0209ac00003'),
          DateTime.utc(2030),
        );
      });

      test('a newer message raises last activity', () async {
        await _insertPost(writer, 'Bm0209ac00004');
        await _insertMessage(writer, 'Rm0209ac0005', 'Bm0209ac00004', _t2030);

        await _insertMessage(writer, 'Rm0209ac0006', 'Bm0209ac00004', _t2031);

        expect(
          await _lastActivity(writer, 'Bm0209ac00004'),
          DateTime.utc(2031),
        );
      });

      test(
        'a reaction bumps the last activity of its message beacon',
        () async {
          await _insertPost(writer, 'Bm0209ac00005');
          await _insertMessage(writer, 'Rm0209ac0007', 'Bm0209ac00005', _t2030);

          await writer.execute('''
INSERT INTO public.beacon_room_message_reaction
  (message_id, user_id, emoji, created_at)
VALUES ('Rm0209ac0007', '$_other', 'x', '$_t2032')
''');

          expect(
            await _lastActivity(writer, 'Bm0209ac00005'),
            DateTime.utc(2032),
          );
        },
      );

      test('a forward edge bumps last activity', () async {
        await _insertPost(writer, 'Bm0209ac00006', status: _statusOpen);

        await writer.execute('''
INSERT INTO public.beacon_forward_edge
  (beacon_id, sender_id, recipient_id, created_at)
VALUES ('Bm0209ac00006', '$_author', '$_other', '$_t2033')
''');

        expect(
          await _lastActivity(writer, 'Bm0209ac00006'),
          DateTime.utc(2033),
        );
      });

      test('the bump function never lowers and fills a null value', () async {
        await _insertBeacon(writer, 'Bm0209ac00007');

        await writer.execute(
          "SELECT public.beacon_bump_last_activity('Bm0209ac00007', "
          "'$_t2031'::timestamptz)",
        );
        expect(
          await _lastActivity(writer, 'Bm0209ac00007'),
          DateTime.utc(2031),
        );

        await writer.execute(
          "SELECT public.beacon_bump_last_activity('Bm0209ac00007', "
          "'$_t2030'::timestamptz)",
        );
        expect(
          await _lastActivity(writer, 'Bm0209ac00007'),
          DateTime.utc(2031),
        );
      });
    });

    group('pinned_at', () {
      test(
        'pinning a beacon stamps the pin time with the insertion time',
        () async {
          await _insertBeacon(writer, 'Bm0209pn00001');

          final before = await _databaseClock(writer);
          await writer.execute('''
INSERT INTO public.beacon_pinned (user_id, beacon_id)
VALUES ('$_other', 'Bm0209pn00001')
''');
          final after = await _databaseClock(writer);

          final pinnedAt =
              (await writer.execute(
                    'SELECT pinned_at FROM public.beacon_pinned '
                    "WHERE beacon_id = 'Bm0209pn00001'",
                  )).single.single
                  as DateTime?;
          expect(pinnedAt, isNotNull);
          expect(pinnedAt!.isBefore(before), isFalse);
          expect(pinnedAt.isAfter(after), isFalse);
        },
      );
    });

    group('post root message', () {
      test('deleting the root message clears the reference', () async {
        await _insertPost(writer, 'Bm0209rt00001');
        await _insertMessage(writer, 'Rm0209rt0001', 'Bm0209rt00001', _t2030);
        await writer.execute(
          "UPDATE public.beacon SET post_root_message_id = 'Rm0209rt0001' "
          "WHERE id = 'Bm0209rt00001'",
        );

        await writer.execute(
          "DELETE FROM public.beacon_room_message WHERE id = 'Rm0209rt0001'",
        );

        final rows = await writer.execute(
          'SELECT post_root_message_id FROM public.beacon '
          "WHERE id = 'Bm0209rt00001'",
        );
        expect(rows.single.single, isNull);
      });
    });
  });
}

final _throwsCheckViolation = throwsA(
  isA<ServerException>().having((e) => e.code, 'sqlstate', _checkViolation),
);

Future<void> _insertUser(Connection writer, String id) => writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id') ON CONFLICT DO NOTHING
''');

Future<void> _insertBeacon(
  Connection writer,
  String id, {
  String? extra,
  String? extraValue,
}) => writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status${extra == null ? '' : ', $extra'})
VALUES ('$id', '$_author', 'Request', 'd', $_statusOpen${extraValue == null ? '' : ', $extraValue'})
''');

Future<void> _insertPost(
  Connection writer,
  String id, {
  int status = _statusDraft,
  int policy = 1,
  bool includePolicy = true,
  String title = '',
  String description = '',
  bool isDiscoverable = false,
  String extraColumns = '',
  String extraValues = '',
}) => writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable
   ${includePolicy ? ', forward_policy' : ''}$extraColumns)
VALUES ('$id', '$_author', '$title', '$description', $status, 1, $isDiscoverable
   ${includePolicy ? ', $policy' : ''}$extraValues)
''');

Future<void> _insertMessage(
  Connection writer,
  String id,
  String beaconId,
  String createdAt, {
  int? systemKind,
}) => writer.execute('''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, created_at, system_message_kind)
VALUES ('$id', '$beaconId', ${systemKind == null ? "'$_author'" : 'NULL'},
        'body', '$createdAt', ${systemKind ?? 'NULL'})
''');

Future<DateTime?> _lastActivity(Connection writer, String beaconId) async {
  final rows = await writer.execute(
    "SELECT last_activity_at FROM public.beacon WHERE id = '$beaconId'",
  );
  return rows.single.single as DateTime?;
}

Future<DateTime> _databaseClock(Connection writer) async =>
    (await writer.execute('SELECT clock_timestamp()')).single.single!
        as DateTime;
