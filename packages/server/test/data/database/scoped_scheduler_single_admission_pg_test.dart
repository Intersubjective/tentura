@Tags(['pg', 'multi-connection'])
library;

import 'dart:async';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';
import 'package:tentura_server/data/database/main_db_pool.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/service/constellation_db_scheduler.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/sentry_trace_capture.dart';

const _admissionWait = 'db.admission.wait';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_SCHEDULER_SINGLE_ADMISSION_TEST_DB',
    defaultNamePrefix: 'tentura_test_sched_single_adm',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  late DisposablePgWriterSession session;
  final capture = SentryTraceCapture();

  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
  });
  tearDownAll(() => tearDownDisposablePgWriter(session: session));
  setUp(capture.start);
  tearDown(capture.stop);

  MainDbPool poolWith({required int connections}) {
    final dbEnv = target.databaseEnv;
    final pool = MainDbPool(
      Env(
        environment: Environment.test,
        printEnv: false,
        isDebugModeOn: false,
        pgHost: dbEnv.pgHost,
        pgPort: dbEnv.pgPort,
        pgDatabase: dbEnv.pgDatabase,
        pgUsername: dbEnv.pgUsername,
        pgPassword: dbEnv.pgPassword,
        maxConnectionCount: connections,
      ),
    );
    addTearDown(pool.close);
    return pool;
  }

  // Two connections leave spare capacity, so a second admission taken by the
  // same work shows up as a count of 2 rather than as a self-wait.
  group('Constellation scheduler and connection scope on one pool', () {
    test('a scope opened inside a scheduled full run holds exactly one '
        'admission slot for the whole run', () async {
      final pool = poolWith(connections: 2);
      final db = TenturaDb.scoped(pool);
      addTearDown(db.close);
      final scheduler = ConstellationDbScheduler.injected(pool);
      final request = capture.beginRequest();
      final slotsInBody = <int>[];
      final slotsInScope = <int>[];

      await scheduler
          .run(ConstellationDbWorkKind.full, () async {
            slotsInBody.add(pool.admission.running);
            await db.withConnectionScope(() async {
              await db.customSelect('SELECT 1 AS one').get();
              slotsInScope.add(pool.admission.running);
            });
            slotsInBody.add(pool.admission.running);
          })
          .timeout(const Duration(seconds: 10));

      final sent = await capture.finish(request);
      expect(slotsInScope, [1]);
      expect(slotsInBody, everyElement(lessThanOrEqualTo(1)));
      expect(sent.spansWithOperation(_admissionWait), hasLength(1));
      expect(pool.admission.running, 0);
    });

    test('a scheduled apply inside an open connection scope runs under the '
        'slot its caller already holds', () async {
      final pool = poolWith(connections: 2);
      final db = TenturaDb.scoped(pool);
      addTearDown(db.close);
      final scheduler = ConstellationDbScheduler.injected(pool);
      final slotsInScope = <int>[];
      final slotsInScheduledBody = <int>[];

      await db
          .withConnectionScope(() async {
            slotsInScope.add(pool.admission.running);
            await scheduler.run(ConstellationDbWorkKind.apply, () async {
              slotsInScheduledBody.add(pool.admission.running);
              await db.customSelect('SELECT 5 AS five').get();
            });
          })
          .timeout(const Duration(seconds: 10));

      expect(slotsInScope, [1]);
      expect(slotsInScheduledBody, [1]);
      expect(pool.admission.running, 0);
    });

    test('a scheduled apply inside an open connection scope completes on a '
        'single-slot pool instead of waiting for the slot its caller holds',
        () async {
      final pool = poolWith(connections: 1);
      final db = TenturaDb.scoped(pool);
      addTearDown(db.close);
      final scheduler = ConstellationDbScheduler.injected(pool);

      final value = await db
          .withConnectionScope(
            () => scheduler.run(
              ConstellationDbWorkKind.apply,
              () async =>
                  (await db.customSelect('SELECT 5 AS five').getSingle())
                      .read<int>('five'),
            ),
          )
          .timeout(const Duration(seconds: 10));

      expect(value, 5);
      expect(pool.admission.running, 0);
    });

    test('nested scheduled full runs around a scope never hold more than one '
        'slot at any depth', () async {
      final pool = poolWith(connections: 2);
      final db = TenturaDb.scoped(pool);
      addTearDown(db.close);
      final scheduler = ConstellationDbScheduler.injected(pool);
      final slotsInOuter = <int>[];
      final slotsInInner = <int>[];
      final slotsInScope = <int>[];

      await scheduler
          .run(ConstellationDbWorkKind.full, () async {
            slotsInOuter.add(pool.admission.running);
            await scheduler.run(ConstellationDbWorkKind.full, () async {
              slotsInInner.add(pool.admission.running);
              await db.withConnectionScope(() async {
                slotsInScope.add(pool.admission.running);
              });
            });
          })
          .timeout(const Duration(seconds: 10));

      expect(slotsInOuter, everyElement(lessThanOrEqualTo(1)));
      expect(slotsInInner, everyElement(lessThanOrEqualTo(1)));
      expect(slotsInScope, [1]);
      expect(pool.admission.running, 0);
    });

    test('nested scheduled full runs around a scope complete on a '
        'single-slot pool', () async {
      final pool = poolWith(connections: 1);
      final db = TenturaDb.scoped(pool);
      addTearDown(db.close);
      final scheduler = ConstellationDbScheduler.injected(pool);

      final slotsInScope = await scheduler
          .run(
            ConstellationDbWorkKind.full,
            () => scheduler.run(
              ConstellationDbWorkKind.full,
              () => db.withConnectionScope(() async => pool.admission.running),
            ),
          )
          .timeout(const Duration(seconds: 10));

      expect(slotsInScope, 1);
    });
  });
}
