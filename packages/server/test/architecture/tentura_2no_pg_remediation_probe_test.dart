// tentura-2no landing gate acceptance (trial merge tentura-50o)

import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../support/disposable_pg_target.dart';

/// Postgres files that failed the tentura-50o pg landing regression (m0202/m0203 drift).
const k2noRegressionPgTestPaths = [
  'test/domain/use_case/review_finalization_outcome_evidence_pg_test.dart',
  'test/domain/use_case/review_obligation_settlement_pg_test.dart',
  'test/domain/use_case/evaluation_submit_ack_policy_pg_test.dart',
  'test/domain/use_case/help_offer_obligation_settlement_pg_test.dart',
  'test/domain/use_case/review_obligation_backfill_pg_test.dart',
  'test/domain/use_case/attention_reconciliation_pg_test.dart',
  'test/data/database/m0201_clamp_pg_test.dart',
  'test/data/repository/evaluation_repository_submit_atomic_pg_test.dart',
  'test/data/repository/evaluation_repository_review_status_pg_test.dart',
  'test/data/repository/trust_maintenance_test.dart',
];

const _legacyReviewSqlFragments = [
  'public.beacon_evaluation_ack_tag',
  'public.beacon_review_window',
  'public.beacon_review_status',
  'beacon_evaluation_ack_tag',
  'beacon_review_window',
  'beacon_review_status',
];

/// pg-tagged probes queue on the cluster-wide disposable-pg lifecycle lock
/// (see `withDisposablePgLifecycleLock`); at shard start that wait can far
/// exceed the default 30s test timeout. A timed-out test body keeps running
/// in the background and keeps consuming the lock, so the timeout must be
/// generous enough to never fire on a healthy run.
const _pgProbeTimeout = Timeout(Duration(minutes: 10));

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_2NO_PG_PROBE_DB',
    defaultNamePrefix: 'tentura_test_2no_probe',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('tentura-2no pg remediation probe (trial merge tentura-50o)', () {
    test('regression pg paths are enumerated for tentura-50o landing', () {
      expect(k2noRegressionPgTestPaths, hasLength(10));
      for (final path in k2noRegressionPgTestPaths) {
        expect(
          File(path).existsSync(),
          isTrue,
          reason: 'missing regression pg test $path',
        );
      }
    });

    test(
      'drift pg test sources omit legacy review-table SQL after m0203',
      () {
        for (final path in k2noRegressionPgTestPaths) {
          final source = File(path).readAsStringSync();
          for (final fragment in _legacyReviewSqlFragments) {
            expect(
              source.contains(fragment),
              isFalse,
              reason:
                  '$path still references $fragment — '
                  'update fixtures for closure schema (tentura-2no)',
            );
          }
        }
      },
    );

    test(
      'drift pg test sources omit legacy trust-ledger SQL after m0202',
      () {
        const trustDriftPaths = [
          'test/data/database/m0201_clamp_pg_test.dart',
          'test/data/repository/trust_maintenance_test.dart',
        ];
        const legacyTrustSqlFragments = [
          'public.user_trust_source_edge',
          'trust_rebuild_effective_batch',
          'meritrank_edge_tombstone',
        ];
        for (final path in trustDriftPaths) {
          final source = File(path).readAsStringSync();
          for (final fragment in legacyTrustSqlFragments) {
            expect(
              source.contains(fragment),
              isFalse,
              reason:
                  '$path still references $fragment — '
                  'update for trust ledger m0202 (tentura-2no)',
            );
          }
        }
      },
    );

    test(
      'migrated disposable schema drops legacy review tables (m0203)',
      () async {
        final session = await setUpDisposablePgWriter(target: target);
        try {
          for (final table in const [
            'beacon_evaluation_ack_tag',
            'beacon_review_window',
            'beacon_review_status',
          ]) {
            final rows = await session.writer.execute(
              Sql.named(r'''
SELECT 1
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name = @name
'''),
              parameters: {'name': table},
            );
            expect(
              rows,
              isEmpty,
              reason: '$table must be absent after migrateDbSchema',
            );
          }
        } finally {
          await tearDownDisposablePgWriter(session: session);
        }
      },
      skip: skipReason,
      tags: ['pg'],
      timeout: _pgProbeTimeout,
    );

    test(
      'migrated disposable schema drops legacy trust ledger tables (m0202)',
      () async {
        final session = await setUpDisposablePgWriter(target: target);
        try {
          for (final table in const [
            'user_trust_source_edge',
            'meritrank_edge_tombstone',
          ]) {
            final rows = await session.writer.execute(
              Sql.named(r'''
SELECT 1
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name = @name
'''),
              parameters: {'name': table},
            );
            expect(
              rows,
              isEmpty,
              reason: '$table must be absent after migrateDbSchema',
            );
          }
          final batchFn = await session.writer.execute(r'''
SELECT count(*)::int > 0 AS ok FROM pg_proc
WHERE proname = 'trust_rebuild_effective_batch'
''');
          expect(
            batchFn.single.single,
            isFalse,
            reason: 'trust_rebuild_effective_batch must be dropped in m0202',
          );
        } finally {
          await tearDownDisposablePgWriter(session: session);
        }
      },
      skip: skipReason,
      tags: ['pg'],
      timeout: _pgProbeTimeout,
    );

    test(
      'trust_maintenance_test tearDown cleanup runs on post-m0202 schema',
      () async {
        final session = await setUpDisposablePgWriter(target: target);
        const aliceId = 'UtmtAlice001';
        const bobId = 'UtmtBob00001';
        try {
          // Mirrors the remediated trust_maintenance_test tearDown: it must
          // run clean on the post-m0202 schema (no legacy ledger tables).
          await session.writer.execute(
            "DELETE FROM public.trust_evidence "
            "WHERE subject_user_id IN ('$aliceId', '$bobId') "
            "OR object_user_id IN ('$aliceId', '$bobId')",
          );
          await session.writer.execute(
            "DELETE FROM public.user_trust_edge "
            "WHERE subject IN ('$aliceId', '$bobId') OR object IN ('$aliceId', '$bobId')",
          );
          await session.writer.execute(
            "DELETE FROM public.trust_publish_queue "
            "WHERE subject_user_id IN ('$aliceId', '$bobId') "
            "OR object_user_id IN ('$aliceId', '$bobId')",
          );
        } finally {
          await tearDownDisposablePgWriter(session: session);
        }
      },
      skip: skipReason,
      tags: ['pg'],
      timeout: _pgProbeTimeout,
    );
  });
}
