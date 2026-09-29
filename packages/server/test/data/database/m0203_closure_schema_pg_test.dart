@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

/// A6 (m0203): closure schema (Arch §5.4), legacy status-5 bump, review table drop,
/// and notification allowlist — see `docs/plans/episode-closure-implementation-steps.md`.
const _authorId = 'Um0203author01';
const _helper1Id = 'Um0203helper01';
const _helper2Id = 'Um0203helper02';
const _reviewerId = 'Um0203review01';
const _beaconId = 'Bm0203fixt001';
const _legacyBeaconId = 'Bm0203legacy1';

Future<void> main() async {
  final migrationTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0203_CLOSURE_MIGRATION_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0203_closure_mig',
  );
  final constraintTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0203_CLOSURE_CONSTRAINT_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0203_closure_chk',
  );
  final reachable = await canReachPostgresAdmin(migrationTarget);
  final skipReason = reachable
      ? false as Object
      : 'Postgres admin database not reachable for disposable test target';

  group('migration from 0202', () {
    late DisposablePgWriterSession session;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(
          target: migrationTarget,
          lastInclusiveVersion: '0202',
        );
        await _seedLegacyReviewWindow(session.writer);
        await migrateDbSchema(session.writer);
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session);
      });
    }

    test(
      'registry reaches 0203',
      () async {
        final version = await session.writer.execute(
          'SELECT max(version COLLATE "C") FROM schema_version',
        );
        expect(version.single.single, '0203');
      },
      skip: skipReason,
    );

    test(
      'legacy reviewOpen requests become needsMoreHelp',
      () async {
        final status = await session.writer.execute(
          Sql.named(
            'SELECT status::int FROM public.beacon WHERE id = @id',
          ),
          parameters: {'id': _legacyBeaconId},
        );
        expect(
          status.single.single,
          BeaconStatus.needsMoreHelp.smallintValue,
        );
      },
      skip: skipReason,
    );

    test(
      'live reviewOpened obligations are superseded like reopen',
      () async {
        final kind = await session.writer.execute(
          Sql.named(r'''
SELECT outbox.settlement_kind
FROM public.notification_outbox AS outbox
JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
WHERE outbox.beacon_id = @beaconId
  AND outbox.account_id = @accountId
  AND occ.event_type = 'reviewOpened'
  AND outbox.requires_action
ORDER BY outbox.created_at DESC
LIMIT 1
'''),
          parameters: {
            'beaconId': _legacyBeaconId,
            'accountId': _reviewerId,
          },
        );
        expect(kind.single.single, 'superseded');
      },
      skip: skipReason,
    );

    test(
      'drops all six review tables',
      () async {
        const dropped = [
          'beacon_evaluation',
          'beacon_evaluation_ack_tag',
          'beacon_evaluation_participant',
          'beacon_evaluation_visibility',
          'beacon_review_status',
          'beacon_review_window',
        ];
        for (final table in dropped) {
          final exists = await _tableExists(session.writer, table);
          expect(exists, isFalse, reason: '$table should be dropped');
        }
      },
      skip: skipReason,
    );

    test(
      'creates all nine beacon_closure tables',
      () async {
        const expected = [
          'beacon_closure',
          'beacon_closure_member',
          'beacon_closure_outcome',
          'beacon_closure_author_split',
          'beacon_closure_support',
          'beacon_closure_commit',
          'beacon_closure_mark',
          'beacon_closure_story',
          'beacon_closure_result',
        ];
        for (final table in expected) {
          final exists = await _tableExists(session.writer, table);
          expect(exists, isTrue, reason: '$table should exist');
        }
      },
      skip: skipReason,
    );

    test(
      'extends recipient_safe presentation keys for closure notifications',
      () async {
        await _insertUser(session.writer, 'Um0203notify01', keySlot: 3);
        final occurrence = await session.writer.execute(
          Sql.named(r'''
INSERT INTO public.attention_occurrence (
  id, source_event_key, event_type, immutable_payload
) VALUES (
  'Occm0203cls01', 'Occm0203cls01', 'closureFixture', '{}'::jsonb
)
RETURNING id
'''),
        );
        final occurrenceId = occurrence.single.single! as String;
        await expectLater(
          session.writer.execute(
            Sql.named(r'''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority, title, body, action_url,
  dedup_key, source_event_key, occurrence_id, destination_kind,
  presentation_key, presentation_payload,
  suppression_class, access_policy, requires_action
) VALUES (
  'Outm0203cls01', 'Um0203notify01', 'coordination', 'fixture', 'normal',
  'Closure', 'Body', '/attention', 'dedup-closure-finalized',
  'Outm0203cls01', @occurrenceId, 'beacon',
  'closure_finalized', '{}'::jsonb,
  'standard', 'recipient_safe', false
)
'''),
            parameters: {'occurrenceId': occurrenceId},
          ),
          completes,
        );
      },
      skip: skipReason,
    );
  });

  group('closure CHECK constraints', () {
    late DisposablePgWriterSession session;

    if (reachable) {
      setUpAll(() async {
        session = await setUpDisposablePgWriter(target: constraintTarget);
      });

      setUp(() async {
        await _resetClosureFixture(session.writer);
      });

      tearDownAll(() async {
        await tearDownDisposablePgWriter(session: session);
      });
    }

    test(
      'author_split rejects pct not divisible by 5',
      () async {
        await _insertClosureEpoch(session.writer, epoch: 1, status: 2);
        await expectLater(
          session.writer.execute(
            Sql.named(r'''
INSERT INTO public.beacon_closure_author_split (beacon_id, helper_id, pct)
VALUES (@beaconId, @helperId, 7)
'''),
            parameters: {'beaconId': _beaconId, 'helperId': _helper1Id},
          ),
          _checkViolation,
        );
      },
      skip: skipReason,
    );

    test(
      'author_split rejects pct above 100',
      () async {
        await _insertClosureEpoch(session.writer, epoch: 1, status: 2);
        await expectLater(
          session.writer.execute(
            Sql.named(r'''
INSERT INTO public.beacon_closure_author_split (beacon_id, helper_id, pct)
VALUES (@beaconId, @helperId, 105)
'''),
            parameters: {'beaconId': _beaconId, 'helperId': _helper1Id},
          ),
          _checkViolation,
        );
      },
      skip: skipReason,
    );

    test(
      'outcome rejects invalid outcome code',
      () async {
        await expectLater(
          session.writer.execute(
            Sql.named(r'''
INSERT INTO public.beacon_closure_outcome (beacon_id, helper_id, outcome)
VALUES (@beaconId, @helperId, 4)
'''),
            parameters: {'beaconId': _beaconId, 'helperId': _helper1Id},
          ),
          _checkViolation,
        );
      },
      skip: skipReason,
    );

    test(
      'support rejects voter equal to target',
      () async {
        await _insertClosureEpoch(session.writer, epoch: 1, status: 2);
        await expectLater(
          session.writer.execute(
            Sql.named(r'''
INSERT INTO public.beacon_closure_support (
  beacon_id, voter_id, target_id, version
) VALUES (@beaconId, @userId, @userId, 0)
'''),
            parameters: {'beaconId': _beaconId, 'userId': _helper1Id},
          ),
          _checkViolation,
        );
      },
      skip: skipReason,
    );

    test(
      'story rejects body longer than 2000 characters',
      () async {
        final body = 'x' * 2001;
        await expectLater(
          session.writer.execute(
            Sql.named(r'''
INSERT INTO public.beacon_closure_story (beacon_id, body)
VALUES (@beaconId, @body)
'''),
            parameters: {'beaconId': _beaconId, 'body': body},
          ),
          _checkViolation,
        );
      },
      skip: skipReason,
    );

    test(
      'partial unique index rejects a second live epoch',
      () async {
        await _insertClosureEpoch(session.writer, epoch: 1, status: 0);
        await expectLater(
          _insertClosureEpoch(session.writer, epoch: 2, status: 1),
          throwsA(
            isA<ServerException>().having(
              (e) => e.code,
              'code',
              anyOf('23505', '23514'),
            ),
          ),
        );
      },
      skip: skipReason,
    );
  });
}

Matcher _checkViolation = throwsA(
  isA<ServerException>().having((e) => e.code, 'code', '23514'),
);

Future<bool> _tableExists(Connection writer, String tableName) async {
  final rows = await writer.execute(
    Sql.named(r'''
SELECT 1
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name = @name
LIMIT 1
'''),
    parameters: {'name': tableName},
  );
  return rows.isNotEmpty;
}

Future<void> _insertUser(
  Connection writer,
  String id, {
  required int keySlot,
}) async {
  await writer.execute(
    Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
ON CONFLICT (id) DO NOTHING
'''),
    parameters: {
      'id': id,
      'key': pgTestPublicKey('m0203_closure', keySlot),
    },
  );
}

Future<void> _seedLegacyReviewWindow(Connection writer) async {
  await _insertUser(writer, _authorId, keySlot: 1);
  await _insertUser(writer, _reviewerId, keySlot: 2);
  await writer.execute(
    Sql.named(r'''
INSERT INTO public.beacon (
  id, user_id, title, description, status, published_at, created_at, updated_at
) VALUES (
  @id, @userId, 'Legacy review window', 'desc',
  @status,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
'''),
    parameters: {
      'id': _legacyBeaconId,
      'userId': _authorId,
      'status': BeaconStatus.reviewOpen.smallintValue,
    },
  );
  await writer.execute(
    Sql.named(r'''
INSERT INTO public.beacon_review_window (
  beacon_id, opened_at, closes_at, status, extensions_used
) VALUES (
  @beaconId,
  '2026-01-01T00:00:00Z',
  '2026-02-01T00:00:00Z',
  0,
  0
)
'''),
    parameters: {'beaconId': _legacyBeaconId},
  );
  final occurrence = await writer.execute(
    Sql.named(r'''
INSERT INTO public.attention_occurrence (
  id, source_event_key, event_type, actor_user_id, immutable_payload
) VALUES (
  'Occm0203leg01', 'Occm0203leg01', 'reviewOpened', @actor, '{}'::jsonb
)
RETURNING id
'''),
    parameters: {'actor': _authorId},
  );
  final occurrenceId = occurrence.single.single! as String;
  await writer.execute(
    Sql.named(r'''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority, title, body, action_url,
  dedup_key, beacon_id, source_event_key, occurrence_id, destination_kind,
  presentation_key, presentation_payload,
  suppression_class, access_policy, requires_action,
  attention_thread_key, logical_task_key, lifecycle_generation
) VALUES (
  'Outm0203leg01', @accountId, 'asksOfMe', 'commitmentEvent', 'normal',
  'Review', 'Review body', '/attention', 'dedup-m0203-legacy',
  @beaconId, 'Outm0203leg01', @occurrenceId, 'beacon',
  'review_opened', '{"eventType":"reviewOpened"}'::jsonb,
  'standard', 'beacon_content', true,
  @threadKey, @logicalKey, 1
)
'''),
    parameters: {
      'accountId': _reviewerId,
      'beaconId': _legacyBeaconId,
      'occurrenceId': occurrenceId,
      'threadKey': 'v1|reviewOpened|$_legacyBeaconId|$_reviewerId',
      'logicalKey':
          'v1|reviewOpened|$_legacyBeaconId|$_legacyBeaconId|$_reviewerId',
    },
  );
}

Future<void> _resetClosureFixture(Connection writer) async {
  await writer.execute(
    "DELETE FROM public.beacon_closure_result WHERE beacon_id = '$_beaconId'",
  );
  for (final table in [
    'beacon_closure_member',
    'beacon_closure_support',
    'beacon_closure_author_split',
    'beacon_closure_outcome',
    'beacon_closure_commit',
    'beacon_closure_mark',
    'beacon_closure_story',
    'beacon_closure',
  ]) {
    await writer.execute(
      "DELETE FROM public.$table WHERE beacon_id = '$_beaconId'",
    );
  }
  await writer.execute(
    "DELETE FROM public.beacon WHERE id = '$_beaconId'",
  );
  for (final id in [_authorId, _helper1Id, _helper2Id]) {
    await writer.execute(
      "DELETE FROM public.\"user\" WHERE id = '$id'",
    );
  }
  await _insertUser(writer, _authorId, keySlot: 4);
  await _insertUser(writer, _helper1Id, keySlot: 5);
  await _insertUser(writer, _helper2Id, keySlot: 6);
  await writer.execute(
    Sql.named(r'''
INSERT INTO public.beacon (
  id, user_id, title, description, status, published_at, created_at, updated_at
) VALUES (
  @id, @userId, 'Closure fixture', 'desc', @status,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
'''),
    parameters: {
      'id': _beaconId,
      'userId': _authorId,
      'status': BeaconStatus.open.smallintValue,
    },
  );
}

Future<void> _insertClosureEpoch(
  Connection writer, {
  required int epoch,
  required int status,
}) async {
  await writer.execute(
    Sql.named(r'''
INSERT INTO public.beacon_closure (
  beacon_id, epoch, status, opened_at, closes_at
) VALUES (
  @beaconId, @epoch, @status,
  '2026-01-01T00:00:00Z', '2026-02-01T00:00:00Z'
)
ON CONFLICT (beacon_id, epoch) DO UPDATE
SET status = EXCLUDED.status
'''),
    parameters: {
      'beaconId': _beaconId,
      'epoch': epoch,
      'status': status,
    },
  );
}
