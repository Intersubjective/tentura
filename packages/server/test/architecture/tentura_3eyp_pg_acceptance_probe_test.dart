// tentura-3eyp landing gate acceptance (parent tentura-jszi)

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import '../support/disposable_pg_target.dart';
import '../support/user_trust_edge_m0202_pg_seed_contract.dart';

const _pgProbeTimeout = Timeout(Duration(minutes: 10));

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_3EYP_PG_PROBE_DB',
    defaultNamePrefix: 'tentura_test_3eyp_probe',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('tentura-3eyp pg acceptance probe (parent tentura-jszi)', () {
    test('regression paths match tentura-3eyp bead enumeration', () {
      expect(k3eypUserTrustEdgeSeedRegressionPaths, hasLength(7));
    });

    test(
      'migrated disposable schema drops user_trust_edge.anchor_at (m0202)',
      () async {
        final session = await setUpDisposablePgWriter(target: target);
        try {
          final rows = await session.writer.execute(
            Sql.named(r'''
SELECT 1
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'user_trust_edge'
  AND column_name = 'anchor_at'
'''),
          );
          expect(rows, isEmpty, reason: 'anchor_at must be absent after m0202');
        } finally {
          await tearDownDisposablePgWriter(session: session);
        }
      },
      timeout: _pgProbeTimeout,
      skip: skipReason,
    );

    test(
      'regression pg sources omit legacy user_trust_edge INSERT columns (m0202)',
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
                '$path still seeds user_trust_edge with m0202-dropped columns '
                '(tentura-3eyp pg probe)',
          );
        }
      },
    );
  });
}
