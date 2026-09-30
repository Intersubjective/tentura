// tentura-6koo acceptance: G3a integration setUp vs m0203 + pg/mr regression.

import 'package:test/test.dart';

import '../support/disposable_pg_target.dart';
import '../support/m0203_dropped_review_sql_usage.dart';
import '../support/tentura_6koo_forward_band_witness_cleanup_harness.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_6KOO_FORWARD_BAND_WITNESS_CLEANUP_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_6koo_g3a_cleanup',
  );
  final reachable = await canReachPostgresAdmin(target);

  group('tentura-6koo forward band witness cleanup acceptance', () {
    test(
      'g3a setUp teardown omits m0203-dropped review-table SQL',
      () {
        final offenders = forwardBandG3aSetUpTeardownLegacyReviewSqlUsage();
        expect(
          offenders,
          isEmpty,
          reason:
              '${kForwardBandWitnessAdmissionIntegrationPgTestPath} setUp '
              'teardown still references legacy review objects dropped in '
              'm0203: $offenders',
        );
      },
    );

    test(
      'g3a setUp teardown DELETE targets exclude m0203-dropped tables',
      () {
        final deleteTargets = forwardBandG3aSetUpTeardownDeleteTableTargets();
        final legacyDeletes = deleteTargets
            .where(m0203DroppedReviewTables.contains)
            .toList()
          ..sort();
        expect(
          legacyDeletes,
          isEmpty,
          reason:
              'setUp teardown still DELETEs from tables absent after m0203: '
              '$legacyDeletes',
        );
      },
    );

    test(
      'g3a setUp _seedBeaconFixture omits m0203-dropped review-table SQL',
      () {
        final offenders = forwardBandG3aSeedFixtureLegacyReviewSqlUsage();
        expect(
          offenders,
          isEmpty,
          reason:
              '${kForwardBandWitnessAdmissionIntegrationPgTestPath} '
              '_seedBeaconFixture still references legacy review objects '
              'dropped in m0203: $offenders',
        );
      },
    );

    test(
      'forward_band_witness_admission_integration_pg_test exits 0 under mr',
      () {
        expect(
          reachable,
          isTrue,
          reason:
              'Postgres admin database must be reachable to verify '
              'forward_band_witness_admission_integration_pg_test under mr',
        );
        final outcome = runForwardBandWitnessAdmissionIntegrationPgTestOnHostTree();
        expect(
          outcome.exitCode,
          0,
          reason:
              'G3a integration setUp must complete on schema >= m0203 and '
              'stay green under mr\n'
              'stdout:\n${outcome.stdout}\n'
              'stderr:\n${outcome.stderr}',
        );
      },
      timeout: const Timeout(Duration(minutes: 16)),
    );
  });
}
