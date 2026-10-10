import 'dart:async';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';
import 'package:tentura_server/data/service/constellation_db_scheduler.dart';
import 'package:tentura_server/env.dart';

Env _env({required bool pinned, required int connections}) => Env(
  environment: Environment.test,
  printEnv: false,
  driftTransactionPinnedPoolEnabled: pinned,
  maxConnectionCount: connections,
);

/// Models Drift's FIFO transaction lane independently of scheduler admission.
final class _SingleLane {
  Future<void> _tail = Future<void>.value();

  Future<void> run(Future<void> Function() body) {
    final result = _tail.then((_) => body());
    _tail = result;
    return result;
  }
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

Future<({List<String> admittedWhileFullRuns, List<String> startedAfterFull})>
_observeFullThenApply(Env env) async {
  final scheduler = ConstellationDbScheduler.fromEnv(env);
  final lane = _SingleLane();
  final admitted = <String>[];
  final started = <String>[];
  final releaseFull = Completer<void>();
  final releaseNextFull = Completer<void>();
  final releaseApply = Completer<void>();
  final jobs = <Future<void>>[];

  Future<void> submit(
    ConstellationDbWorkKind kind,
    String name,
    Completer<void> release,
  ) => scheduler.run(kind, () {
    admitted.add(name);
    return lane.run(() async {
      started.add(name);
      await release.future;
    });
  });

  try {
    jobs.add(submit(ConstellationDbWorkKind.full, 'full', releaseFull));
    await _settle();
    // Let admission run before the write arrives: this exposes a refresh
    // parked inside Drift rather than merely testing simultaneous submissions.
    jobs.add(
      submit(ConstellationDbWorkKind.full, 'next full', releaseNextFull),
    );
    await _settle();
    jobs.add(submit(ConstellationDbWorkKind.apply, 'apply', releaseApply));
    await _settle();
    final admittedWhileFullRuns = List<String>.of(admitted);

    releaseFull.complete();
    await jobs.first;
    await _settle();
    return (
      admittedWhileFullRuns: admittedWhileFullRuns,
      startedAfterFull: List<String>.of(started),
    );
  } finally {
    // Drain every job even when an assertion fails in the caller.
    for (final release in [releaseFull, releaseNextFull, releaseApply]) {
      if (!release.isCompleted) release.complete();
    }
    await Future.wait(jobs);
  }
}

void main() {
  group('Constellation DB admission follows effective pool lanes', () {
    for (final mode in [
      (name: 'statement transactions', pinned: false, connections: 8),
      (name: 'pinned transactions', pinned: true, connections: 1),
    ]) {
      group(mode.name, () {
        Env env() => _env(pinned: mode.pinned, connections: mode.connections);

        test('admits one transaction for the single effective DB lane', () {
          final databaseEnv = env();
          expect(databaseEnv.pgPoolSettings.maxConnectionCount, 1);
          final config = ConstellationDbSchedulerConfig.fromEnv(databaseEnv);
          expect(config.queueDeadline, const Duration(seconds: 10));
          expect(config.maxQueued, 1000);
          expect(config.maxConcurrent, 1);
        });

        test('keeps another FULL outside the occupied Drift lane', () async {
          final observed = await _observeFullThenApply(env());
          expect(observed.admittedWhileFullRuns, ['full']);
        });

        test(
          'starts queued apply immediately after the running FULL',
          () async {
            final observed = await _observeFullThenApply(env());
            expect(observed.startedAfterFull, ['full', 'apply']);
          },
        );
      });
    }

    test('derives admission capacity from a pinned multi-lane pool', () {
      final env = _env(pinned: true, connections: 3);
      expect(env.pgPoolSettings.maxConnectionCount, 3);
      expect(ConstellationDbSchedulerConfig.fromEnv(env).maxConcurrent, 3);
    });
  });
}
