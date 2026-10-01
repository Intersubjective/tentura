// tentura-2no landing gate acceptance (trial merge tentura-50o)

import 'dart:io';

import 'package:test/test.dart';

/// Postgres files that failed the tentura-50o pg landing regression (m0202/m0203 drift).
const k2noRegressionPgTestPaths = [
  'test/domain/use_case/help_offer_obligation_settlement_pg_test.dart',
  'test/domain/use_case/attention_reconciliation_pg_test.dart',
  'test/data/database/m0201_clamp_pg_test.dart',
  'test/data/repository/trust_maintenance_test.dart',
];

const _legacyTrustSqlFragments = [
  'public.user_trust_source_edge',
  'trust_rebuild_effective_batch',
  'meritrank_edge_tombstone',
];

/// Alloy tentura-2no landing gate — same paths as bead acceptance harness.
const k2noAcceptanceTestPaths = [
  'test/architecture/tentura_2no_landing_check_test.dart',
  'test/architecture/tentura_2no_pg_remediation_probe_test.dart',
];

/// Alloy tentura-fx7 landing gate — tracked here so the tentura-50o trial
/// merge landing follows fx7 (kept out of [k2noAcceptanceTestPaths]: those
/// files carry the fx7 landing gate marker, not the 2no one).
const k2noFx7AcceptanceTestPaths = [
  'test/architecture/tentura_fx7_landing_check_test.dart',
  'test/architecture/tentura_fx7_pg_acceptance_probe_test.dart',
];

const _2noLandingGateMarker =
    'tentura-2no landing gate acceptance (trial merge tentura-50o)';

const _trialMergeMarker = 'trial merge tentura-50o';

void main() {
  group('tentura-2no landing check (trial merge tentura-50o)', () {
    test('2no acceptance test paths declare 2no landing gate markers', () {
      for (final path in k2noAcceptanceTestPaths) {
        final file = File(path);
        expect(
          file.existsSync(),
          isTrue,
          reason: 'missing acceptance path $path',
        );
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_2noLandingGateMarker),
          reason:
              '$path must tag the 2no landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_trialMergeMarker),
          reason: '$path must reference trial merge tentura-50o',
        );
      }
    });

    test(
      'drift pg test sources omit legacy trust-ledger SQL after m0202',
      () {
        const trustDriftPaths = [
          'test/data/database/m0201_clamp_pg_test.dart',
          'test/data/repository/trust_maintenance_test.dart',
        ];
        for (final path in trustDriftPaths) {
          final source = _serverTestSource(path);
          for (final fragment in _legacyTrustSqlFragments) {
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
  });
}

Directory _serverPackageRoot() {
  for (final path in const ['.', '../../packages/server']) {
    final dir = Directory(path);
    final candidate = File('${dir.path}/lib/env.dart');
    if (candidate.existsSync()) {
      return dir.absolute;
    }
  }
  throw StateError('server package root not found');
}

String _serverTestSource(String relativePath) {
  final file = File('${_serverPackageRoot().path}/$relativePath');
  if (!file.existsSync()) {
    throw StateError('server test file not found: ${file.path}');
  }
  return file.readAsStringSync();
}
