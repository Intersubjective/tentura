// tentura-6koo acceptance: G3a integration setUp vs m0203 (pg run lives in the test-pg job).

import 'package:test/test.dart';

import '../support/m0203_dropped_review_sql_usage.dart';

void main() {
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
  });
}
