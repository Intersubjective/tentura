/// Shared contract helpers: detect SQL usage of review objects dropped in m0203.
library;

import 'm0202_dropped_trust_sql_usage.dart';
import 'user_trust_edge_m0202_pg_seed_contract.dart';

const kForwardBandWitnessAdmissionIntegrationPgTestPath =
    'test/domain/use_case/forward_band_witness_admission_integration_pg_test.dart';

const kForwardBandG3aIntegrationCleanupSupportPath =
    'test/support/forward_band_witness_g3a_pg_cleanup.dart';

const kForwardBandG3aIntegrationCleanupSymbol =
    'forwardBandWitnessG3aIntegrationCleanup';

/// Tables removed in migration m0203 (closure schema cutover).
const m0203DroppedReviewTables = [
  'beacon_evaluation',
  'beacon_evaluation_ack_tag',
  'beacon_evaluation_participant',
  'beacon_evaluation_visibility',
  'beacon_review_status',
  'beacon_review_window',
];

Map<String, List<int>> droppedReviewSqlUsageInSource(String source) {
  final offenders = <String, List<int>>{};
  for (final object in m0203DroppedReviewTables) {
    final lines = sqlUsageLineNumbers(source, object);
    if (lines.isNotEmpty) {
      offenders[object] = lines;
    }
  }
  return offenders;
}

void _mergeOffenders(
  Map<String, List<int>> into,
  Map<String, List<int>> from,
) {
  for (final entry in from.entries) {
    into.putIfAbsent(entry.key, () => []).addAll(entry.value);
  }
}

/// Legacy review SQL in whatever teardown setUp runs before each case.
Map<String, List<int>> forwardBandG3aSetUpTeardownLegacyReviewSqlUsage() {
  final integrationSource = readServerTestSource(
    kForwardBandWitnessAdmissionIntegrationPgTestPath,
  );
  final offenders = <String, List<int>>{};

  if (RegExp(r'Future<void>\s+_cleanup\s*\(').hasMatch(integrationSource)) {
    final body = extractDartFunctionBody(integrationSource, '_cleanup');
    _mergeOffenders(offenders, droppedReviewSqlUsageInSource(body));
  }

  if (integrationSource.contains(kForwardBandG3aIntegrationCleanupSymbol)) {
    final supportSource = readServerTestSource(
      kForwardBandG3aIntegrationCleanupSupportPath,
    );
    final body = extractDartFunctionBody(
      supportSource,
      kForwardBandG3aIntegrationCleanupSymbol,
    );
    _mergeOffenders(offenders, droppedReviewSqlUsageInSource(body));
  }

  return offenders;
}

Set<String> forwardBandG3aSetUpTeardownDeleteTableTargets() {
  final integrationSource = readServerTestSource(
    kForwardBandWitnessAdmissionIntegrationPgTestPath,
  );
  final targets = <String>{};

  if (RegExp(r'Future<void>\s+_cleanup\s*\(').hasMatch(integrationSource)) {
    final body = extractDartFunctionBody(integrationSource, '_cleanup');
    targets.addAll(deletePublicTableTargets(body));
  }

  if (integrationSource.contains(kForwardBandG3aIntegrationCleanupSymbol)) {
    final supportSource = readServerTestSource(
      kForwardBandG3aIntegrationCleanupSupportPath,
    );
    final body = extractDartFunctionBody(
      supportSource,
      kForwardBandG3aIntegrationCleanupSymbol,
    );
    targets.addAll(deletePublicTableTargets(body));
  }

  return targets;
}

/// Legacy review SQL in integration setUp beacon seed (runs after teardown).
Map<String, List<int>> forwardBandG3aSeedFixtureLegacyReviewSqlUsage() {
  final source = readServerTestSource(
    kForwardBandWitnessAdmissionIntegrationPgTestPath,
  );
  final body = extractDartFunctionBody(source, '_seedBeaconFixture');
  return droppedReviewSqlUsageInSource(body);
}
