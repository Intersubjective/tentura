@Tags(['pg'])
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:postgres/postgres.dart' show Connection, Endpoint;
import 'package:test/test.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/drift_executor_wait_guard.dart';

// Match the existing leased-scope regression's deadline and caller timeout.
// Repetition under CPU load checks exception delivery and recovery, without a
// tighter elapsed window that would also constrain scheduling and diagnostics.
const _deadline = Duration(seconds: 2);
const _callerTimeout = Duration(seconds: 20);
const _advisoryKey = 7240127;

Env _connectionEnv(Endpoint endpoint, {int? port}) => Env(
  environment: 'test',
  pgHost: port == null ? endpoint.host : InternetAddress.loopbackIPv4.address,
  pgPort: port ?? endpoint.port,
  pgDatabase: endpoint.database,
  pgUsername: endpoint.username,
  pgPassword: endpoint.password,
  maxConnectionCount: 1,
  constellationDbMaxConcurrent: 1,
  printEnv: false,
  isDebugModeOn: false,
);

/// Holds only the real guard's administrative connection handshake. When
/// released, it forwards the unmodified PostgreSQL protocol; neither
/// DbWaitGuard nor its expiry callback is replaced by a fake.
final class _DelayedAdminProxy {
  _DelayedAdminProxy(this.server, this.upstream) {
    server.listen((client) {
      accepted++;
      sockets.add(client);
      unawaited(_forward(client));
    });
  }

  final ServerSocket server;
  final Endpoint upstream;
  final sockets = <Socket>[];
  final forwarding = <Future<void>>[];
  final errors = <Object>[];
  final _releaseHandshake = Completer<void>();
  int accepted = 0;
  bool closed = false;

  Future<void> _forward(Socket client) async {
    try {
      await _releaseHandshake.future;
      if (closed) return;
      final backend = await Socket.connect(upstream.host, upstream.port);
      sockets.add(backend);
      if (closed) {
        backend.destroy();
        return;
      }
      // Listen immediately after connecting: the client's startup packet is
      // buffered until then, reproducing a slow admin handshake under load.
      final streams = Future.wait([
        backend.addStream(client).then((_) => backend.close()),
        client.addStream(backend).then((_) => client.close()),
      ]).then<void>((_) {});
      forwarding.add(streams);
      await streams;
    } on SocketException {
      // A bounded guard may cancel its admin connection while the handshake
      // is delayed. Peer cancellation is normal proxy shutdown, not a fault
      // in the test fixture.
      client.destroy();
    } on Object catch (error) {
      if (!closed) errors.add(error);
    }
  }

  void releaseHandshake() {
    if (!_releaseHandshake.isCompleted) _releaseHandshake.complete();
  }

  Future<void> close() async {
    closed = true;
    releaseHandshake();
    await server.close();
    for (final socket in sockets) {
      socket.destroy();
    }
    await Future.wait(forwarding).catchError((Object _) => <void>[]);
  }
}

void _burnCpu(SendPort ready) {
  ready.send(true);
  var value = 1;
  while (true) {
    for (var i = 0; i < 1000000; i++) {
      value = (value * 1664525 + 1013904223) & 0x7fffffff;
    }
    // Make the computation observable without flooding the test isolate.
    if (value == 0) ready.send(value);
  }
}

Future<void> _expectBackendGone(DisposablePgTarget target, int pid) async {
  final clock = Stopwatch()..start();
  while (clock.elapsed < _callerTimeout) {
    if (!(await readDbActivity(target)).any((row) => row['pid'] == pid)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('leased backend $pid survived the wait failure');
}

Future<void> _expectLockWaitRecovery(
  DisposablePgTarget target,
  _DelayedAdminProxy proxy, {
  required bool delayedAdmin,
}) async {
  final blocker = await Connection.open(
    target.databaseEnv.pgEndpoint,
    settings: target.databaseEnv.pgEndpointSettings,
  );
  final guardTarget = DisposablePgTarget(
    adminEnv: delayedAdmin
        ? _connectionEnv(target.adminEnv.pgEndpoint, port: proxy.server.port)
        : target.adminEnv,
    databaseEnv: _connectionEnv(target.databaseEnv.pgEndpoint),
    templateEnv: target.templateEnv,
    databaseName: target.databaseName,
    envVarName: target.envVarName,
  );
  final db = openDisposablePgDatabase(guardTarget, waitDeadline: _deadline);
  final acceptedBefore = proxy.accepted;
  final statementStarted = Completer<void>();
  int? waitingPid;
  try {
    final blockerPid =
        (await blocker.execute('SELECT pg_backend_pid()')).first.first! as int;
    await blocker.execute('SELECT pg_advisory_lock($_advisoryKey)');

    final waiting = db
        .withConnectionScope(() async {
          await db.customStatement('SET lock_timeout = 0');
          final row = await db
              .customSelect('SELECT pg_backend_pid() AS pid')
              .getSingle();
          waitingPid = row.read<int>('pid');
          statementStarted.complete();
          return db
              .customSelect(
                'SELECT pg_advisory_lock($_advisoryKey) AS locked',
              )
              .get();
        })
        .then<Object?>((_) => null, onError: (Object error) => error);

    final setup =
        await Future.any<Object?>([
          statementStarted.future.then<Object?>((_) => true),
          waiting,
        ]).timeout(
          const Duration(seconds: 10),
          onTimeout: () => TimeoutException('leased statement did not start'),
        );
    expect(
      setup,
      isTrue,
      reason:
          'lease acquisition and warmup must finish before measuring the '
          'blocked statement; a setup hang must not mimic the caller timeout',
    );
    final failure = await waiting.timeout(
      _callerTimeout,
      onTimeout: () => TimeoutException('leased scope exceeded caller timeout'),
    );

    expect(failure, isA<DbWaitTimeoutException>());
    final timeout = failure! as DbWaitTimeoutException;
    expect(timeout.operation, 'runSelect');
    expect(timeout.sql, contains('pg_advisory_lock'));
    expect(timeout.deadline, _deadline);
    expect(waitingPid, isNotNull);
    await _expectBackendGone(target, waitingPid!);
    expect(
      (await readDbActivity(target)).any((row) => row['pid'] == blockerPid),
      isTrue,
      reason: 'the guard must abort the waiter without aborting its blocker',
    );
    // Keep the lock held until after pool recovery, so releasing the blocker
    // cannot rescue a broken timeout/abort implementation.
    final after = await db
        .customSelect('SELECT 1 AS ok')
        .getSingle()
        .timeout(_callerTimeout);
    expect(after.read<int>('ok'), 1);
    if (delayedAdmin) {
      expect(
        proxy.accepted,
        greaterThan(acceptedBefore),
        reason: 'the real diagnostics/abort connection must be exercised',
      );
    }
  } finally {
    if (delayedAdmin) proxy.releaseHandshake();
    // Unlock only for cleanup, after all recovery assertions have run.
    await blocker.close();
    await db.close();
  }
}

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_LEASED_LOCK_DEADLINE_TEST_DB',
    defaultNamePrefix: 'tentura_test_leased_lock_deadline',
  );
  final skipReason = await pgSkipReason(target);
  if (skipReason != null) {
    test('Postgres unavailable', () {}, skip: skipReason);
    return;
  }
  late DisposablePgWriterSession session;
  setUpAll(() async {
    session = await setUpDisposablePgWriter(target: target);
  });
  tearDownAll(() => tearDownDisposablePgWriter(session: session));

  group('leased lock wait recovery', () {
    for (final cpuLoad in [false, true]) {
      group(cpuLoad ? 'under CPU contention' : 'without added CPU load', () {
        test(
          'expired statements abort their lease and leave the pool usable',
          () async {
            final workers = <Isolate>[];
            final proxy = _DelayedAdminProxy(
              await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
              target.adminEnv.pgEndpoint,
            );
            try {
              if (cpuLoad) {
                for (var i = 0; i < 4; i++) {
                  final ready = ReceivePort();
                  try {
                    workers.add(await Isolate.spawn(_burnCpu, ready.sendPort));
                    expect(
                      await ready.first.timeout(const Duration(seconds: 10)),
                      isTrue,
                    );
                  } finally {
                    ready.close();
                  }
                }
              }
              final failures = <String>[];
              for (var run = 1; run <= 20; run++) {
                // Replay the original two-second-deadline path consecutively.
                // Retain every exception/abort/recovery assertion in every run.
                try {
                  await _expectLockWaitRecovery(
                    target,
                    proxy,
                    delayedAdmin: false,
                  );
                } on TestFailure catch (error) {
                  failures.add('run $run: $error');
                }
              }
              // Independently hold the real admin handshake beyond the original
              // caller cap. This makes an unbounded diagnostics/abort path red
              // deterministically, without a tight wall-clock assertion under
              // load. Pool recovery must work while this handshake is held.
              try {
                await _expectLockWaitRecovery(
                  target,
                  proxy,
                  delayedAdmin: true,
                );
              } on TestFailure catch (error) {
                failures.add('stalled admin handshake: $error');
              }
              expect(proxy.errors, isEmpty);
              expect(failures, isEmpty);
            } finally {
              for (final worker in workers) {
                worker.kill(priority: Isolate.immediate);
              }
              await proxy.close();
            }
          },
          timeout: const Timeout(Duration(minutes: 10)),
        );
      });
    }
  });
}
