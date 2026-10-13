import 'dart:async';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';
import 'package:tentura_server/data/service/constellation_db_scheduler.dart';
import 'package:tentura_server/env.dart';

Env _env({required int connections}) => Env(
  environment: Environment.test,
  printEnv: false,
  maxConnectionCount: connections,
  constellationDbMaxConcurrent: 1,
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
  group(
    'Constellation DB admission on the configured pool lanes',
    () {
      for (final mode in [
        (name: 'multiple connections', connections: 8),
        (name: 'single connection', connections: 1),
      ]) {
        group(mode.name, () {
          Env env() => _env(connections: mode.connections);

          test(
            'uses configured pool capacity and bounded queue defaults',
            () {
              final databaseEnv = env();
              expect(
                databaseEnv.pgPoolSettings.maxConnectionCount,
                mode.connections,
              );
              final config = ConstellationDbSchedulerConfig.fromEnv(
                databaseEnv,
              );
              expect(config.queueDeadline, const Duration(seconds: 1));
              expect(config.maxQueued, 32);
              expect(config.maxConcurrent, 1);
            },
          );

          test(
            'admits light work during a FULL when a pool slot is free',
            () async {
              final observed = await _observeFullThenApply(env());
              expect(
                observed.admittedWhileFullRuns,
                mode.connections == 1 ? ['full'] : ['full', 'apply'],
              );
              expect(
                observed.startedAfterFull,
                ['full', 'apply'],
              );
            },
          );
        });
      }

      test(
        'a multi-lane pool does not change the configured slot count',
        () {
          final env = _env(connections: 2);
          expect(env.pgPoolSettings.maxConnectionCount, 2);
          expect(ConstellationDbSchedulerConfig.fromEnv(env).maxConcurrent, 1);
        },
      );

      test('a large pool does not lift admission past its own knob', () {
        final env = _env(connections: 20);
        expect(ConstellationDbSchedulerConfig.fromEnv(env).maxConcurrent, 1);
        final raised = Env(
          environment: Environment.test,
          printEnv: false,
          maxConnectionCount: 20,
          constellationDbMaxConcurrent: 3,
        );
        expect(ConstellationDbSchedulerConfig.fromEnv(raised).maxConcurrent, 3);
      });
    },
  );
}
