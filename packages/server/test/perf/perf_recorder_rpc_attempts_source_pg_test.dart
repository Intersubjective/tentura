// `perf` suites are timing-sensitive, so like `mr` suites they run serialised
// (`-j 1`) and outside the default and plain-`pg` runs.
@Tags(['perf', 'pg', 'mr'])
library;

import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;

import '../support/disposable_pg_target.dart';
import 'perf_recorder.dart';

/// The perf recorder's connector RPC count is the delta of the database's own
/// `mrRpcAttempts()` (the API the RPC-count gate of the constellation
/// transactions reads), not a separate counter read on some other path. The
/// database below reports a scripted counter that the real backend never
/// moves, so only a recorder that reads `TenturaDb.mrRpcAttempts()` can see it.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_PERF_RECORDER_RPC_SOURCE_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_perf_rpc_source',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }

  group('connector RPC count of the perf recorder', () {
    late DisposablePgWriterSession session;
    late PerfDbMeter meter;
    late _ScriptedRpcDb db;
    late PerfRecorder recorder;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() {
      meter = PerfDbMeter();
      db = _ScriptedRpcDb(
        PgDatabase.opened(
          meter.instrument(
            Pool<dynamic>.withEndpoints(
              [target.databaseEnv.pgEndpoint],
              settings: target.databaseEnv.pgPoolSettings,
            ),
          ),
          enableMigrations: false,
        ).interceptWith(meter),
      );
      recorder = PerfRecorder(
        fixture: 'rpc_source',
        db: db,
        meter: meter,
        probeConnection: session.writer,
      );
    });

    tearDown(() => db.close());

    test('is the delta of the database mrRpcAttempts() across the attempt',
        () async {
      db.attempts = 40;

      await recorder.attempt((_) async {
        db.attempts += 7;
      });

      final section =
          recorder.report.toJson()['connectorRpcs']! as Map<String, Object?>;
      expect(section['total'], 7);
    });

    test('an attempt during which the database counter does not move counts '
        'zero', () async {
      db.attempts = 40;

      await recorder.attempt((_) async {});

      final section =
          recorder.report.toJson()['connectorRpcs']! as Map<String, Object?>;
      expect(section['total'], 0);
    });
  });
}

/// A database whose `mrRpcAttempts()` is a counter the test moves by hand.
final class _ScriptedRpcDb extends TenturaDb {
  _ScriptedRpcDb(QueryExecutor executor) : super.forTest(database: executor);

  int attempts = 0;

  @override
  Future<int> mrRpcAttempts() async => attempts;
}
