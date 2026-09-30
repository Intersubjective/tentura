// tentura-3eyp landing gate acceptance (parent tentura-jszi)

import 'dart:io';

import 'package:test/test.dart';

import '../support/user_trust_edge_m0202_pg_seed_contract.dart';

/// Alloy tentura-3eyp landing gate — pg seed drift on `user_trust_edge`.
const k3eypAcceptanceTestPaths = [
  'test/architecture/tentura_3eyp_landing_check_test.dart',
  'test/architecture/tentura_3eyp_pg_acceptance_probe_test.dart',
];

const _3eypLandingGateMarker =
    'tentura-3eyp landing gate acceptance (parent tentura-jszi)';

const _parentBeadMarker = 'parent tentura-jszi';

void main() {
  group('tentura-3eyp landing check (parent tentura-jszi)', () {
    test('3eyp acceptance test paths declare 3eyp landing gate markers', () {
      for (final path in k3eypAcceptanceTestPaths) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'missing acceptance path $path');
        final source = file.readAsStringSync();
        expect(
          source,
          contains(_3eypLandingGateMarker),
          reason:
              '$path must tag the 3eyp landing gate for Alloy trial-merge tracking',
        );
        expect(
          source,
          contains(_parentBeadMarker),
          reason: '$path must reference parent bead tentura-jszi',
        );
      }
    });

    test('3eyp regression pg paths are enumerated for jszi trust-seed landing', () {
      expect(k3eypUserTrustEdgeSeedRegressionPaths, hasLength(6));
      for (final path in k3eypUserTrustEdgeSeedRegressionPaths) {
        expect(
          File('${serverPackageRoot().path}/$path').existsSync(),
          isTrue,
          reason: 'missing regression pg test $path',
        );
      }
    });

    test(
      'pg test seeds omit dropped m0202 columns from user_trust_edge INSERT lists',
      () {
        for (final path in k3eypUserTrustEdgeSeedRegressionPaths) {
          final source = readServerTestSource(path);
          if (!source.contains('INSERT INTO public.user_trust_edge')) {
            continue;
          }
          expect(
            sourceInsertsLegacyUserTrustEdgeColumns(source),
            isFalse,
            reason:
                '$path still INSERTs dropped user_trust_edge columns '
                '(anchor_at or legacy tier bins) — update seeds for m0202 '
                '(tentura-3eyp)',
          );
        }
      },
    );

    test(
      'pg test fixtures omit dropped m0202 columns from user_trust_edge SELECT lists',
      () {
        for (final path in k3eypUserTrustEdgeSeedRegressionPaths) {
          final source = readServerTestSource(path);
          expect(
            sourceSelectsLegacyUserTrustEdgeColumns(source),
            isFalse,
            reason:
                '$path still SELECTs dropped user_trust_edge columns — '
                'read trust_w/wall_d/target_w after m0202 (tentura-3eyp)',
          );
        }
      },
    );

    test(
      'm0202 migration documents DROP COLUMN anchor_at on user_trust_edge',
      () {
        final migration = readServerTestSource(
          'lib/data/database/migration/m0202.dart',
        );
        expect(
          migration,
          contains('DROP COLUMN anchor_at'),
          reason: 'm0202 must drop user_trust_edge.anchor_at (tentura-3eyp AC)',
        );
      },
    );
  });
}
