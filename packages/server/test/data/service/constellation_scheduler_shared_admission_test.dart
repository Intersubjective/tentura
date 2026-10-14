import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/service/constellation_db_scheduler.dart';
import 'package:tentura_server/env.dart';

/// A pool-backed scheduler shares the pool's admission, so its capacity is the
/// pool's connection budget. Nothing here opens a connection.
MainDbPool _pool({required int connections}) => MainDbPool(
  Env(
    environment: Environment.test,
    printEnv: false,
    isDebugModeOn: false,
    maxConnectionCount: connections,
  ),
);

void main() {
  group('Constellation scheduler over the pool admission', () {
    test('a full run nested in a full run completes on a single-slot '
        'admission instead of waiting for its own slot', () async {
      final pool = _pool(connections: 1);
      addTearDown(pool.close);
      final scheduler = ConstellationDbScheduler.injected(pool);

      final result = await scheduler
          .run(
            ConstellationDbWorkKind.full,
            () => scheduler.run(ConstellationDbWorkKind.full, () async => 'ok'),
          )
          .timeout(const Duration(seconds: 5));

      expect(result, 'ok');
    });

    test('an apply nested in a full run completes on a single-slot '
        'admission instead of being refused as a re-entry', () async {
      final pool = _pool(connections: 1);
      addTearDown(pool.close);
      final scheduler = ConstellationDbScheduler.injected(pool);

      final result = await scheduler
          .run(
            ConstellationDbWorkKind.full,
            () => scheduler.run(ConstellationDbWorkKind.apply, () async => 7),
          )
          .timeout(const Duration(seconds: 5));

      expect(result, 7);
    });
  });
}
