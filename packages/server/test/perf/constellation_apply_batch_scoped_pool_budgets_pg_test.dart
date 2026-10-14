// applyBatch through the production-wired main pool (MainDbPool leasing one
// connection per scope, capacity 4 as dev runs it) must meet the same warm
// budgets as the raw-pool measurement.
@Tags(['perf', 'pg', 'mr', 'multi-connection'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_server/env.dart';

import '../support/constellation_apply_batch_perf_fixture.dart';
import '../support/disposable_pg_target.dart';
import 'perf_fixtures.dart';

const _attempts = 30;
const _warmUpCalls = 5;

double _percentile(List<int> sortedMicros, double q) =>
    sortedMicros[((sortedMicros.length - 1) * q).ceil()] / 1000;

void main() {
  group('applyBatch latency on the scoped main pool with capacity 4', () {
    for (final batch in [1, 64]) {
      test('$batch-op batch meets the warm p50 and p95 budgets', () async {
        final fixture = requireApplyBatchPerfFixture(batch);
        final target = DisposablePgTarget.fromNamedEnvironment(
          envVarName: 'TENTURA_APPLY_BATCH_SCOPED_POOL_TEST_DB',
          defaultNamePrefix: 'tentura_test_apply_batch_scoped',
        );
        final session = await setUpDisposablePgWriter(
          target: target,
          createPgmer2Extension: true,
        );
        addTearDown(() => tearDownDisposablePgWriter(session: session));
        final seed = await fixture.seed(session.writer);
        await requireNonEmptyMeritRankGraph(session.writer);

        final db = target.databaseEnv;
        final pool = MainDbPool(
          Env(
            environment: Environment.test,
            printEnv: false,
            isDebugModeOn: false,
            pgHost: db.pgEndpoint.host,
            pgPort: db.pgEndpoint.port,
            pgDatabase: db.pgEndpoint.database,
            pgUsername: db.pgEndpoint.username,
            pgPassword: db.pgEndpoint.password,
            maxConnectionCount: 4,
          ),
        );
        final tentura = TenturaDb.scoped(pool);
        addTearDown(() async {
          await tentura.close();
          await pool.close();
        });
        expect(pool.admission.maxConcurrent, 4);
        final repository = ConstellationAnchorRepository(tentura);

        Future<int> attempt(String prefix, int n) async {
          final watch = Stopwatch()..start();
          final result = await repository.applyBatch(
            viewerId: seed.viewerId,
            ops: [
              for (var i = 0; i < batch; i++)
                AnchorApplyOp(
                  clientOpId: '$prefix-$i',
                  kind: AnchorOpKind.upsert,
                  target: ConstellationAnchorTarget.person(seed.peerIds[i]),
                  position: ConstellationAnchorPosition(
                    xUnits: ((n + i) % 9) - 4.0,
                    yUnits: ((n * 3 + i) % 9) - 4.0,
                    coordinateSpaceVersion: 1,
                  ),
                ),
            ],
          );
          watch.stop();
          expect(
            result.results.every((r) => r.status == AnchorOpStatus.ok),
            isTrue,
          );
          return watch.elapsedMicroseconds;
        }

        for (var w = 0; w < _warmUpCalls; w++) {
          await attempt('scoped-w$batch-a$w', w);
        }
        final micros = [
          for (var n = 0; n < _attempts; n++)
            await attempt('scoped-b$batch-a$n', n),
        ]..sort();

        final (p50Budget, p95Budget) = applyBatchWarmBudgetsMs[batch]!;
        final p50 = _percentile(micros, 0.5);
        final p95 = _percentile(micros, 0.95);
        expect(p50, lessThanOrEqualTo(p50Budget), reason: 'p50 $p50 ms');
        expect(p95, lessThanOrEqualTo(p95Budget), reason: 'p95 $p95 ms');
      }, timeout: const Timeout(Duration(minutes: 30)));
    }
  });
}
