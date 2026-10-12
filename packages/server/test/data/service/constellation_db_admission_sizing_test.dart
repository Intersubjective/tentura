import 'dart:async';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';
import 'package:tentura_server/data/service/constellation_db_scheduler.dart';
import 'package:tentura_server/env.dart';

Env _env({required int connections, int? constellationDbMaxConcurrent}) => Env(
  environment: Environment.test,
  printEnv: false,
  maxConnectionCount: connections,
  constellationDbMaxConcurrent: constellationDbMaxConcurrent,
);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('Constellation admission sizing is independent of the DB pool', () {
    test('pool size does not change maxConcurrent', () {
      final sizes = {
        for (final connections in [1, 2, 8, 20])
          ConstellationDbSchedulerConfig.fromEnv(
            _env(connections: connections),
          ).maxConcurrent,
      };
      expect(sizes, hasLength(1));
    });

    test('the default maxConcurrent is the env knob default', () {
      final env = _env(connections: 1);
      expect(
        ConstellationDbSchedulerConfig.fromEnv(env).maxConcurrent,
        env.constellationDbMaxConcurrent,
      );
    });

    test('an explicit knob sets maxConcurrent whatever the pool size', () {
      for (final connections in [1, 20]) {
        final config = ConstellationDbSchedulerConfig.fromEnv(
          _env(connections: connections, constellationDbMaxConcurrent: 3),
        );
        expect(config.maxConcurrent, 3, reason: 'pool=$connections');
      }
    });
  });

  group('Constellation admission write starvation', () {
    // Every configured slot is held by a long FULL read; a write must still
    // get through (the policy is the implementation's choice).
    const slots = 2;

    test('a queued write starts while FULL reads occupy every slot', () async {
      final scheduler = ConstellationDbScheduler(
        config: const ConstellationDbSchedulerConfig(maxConcurrent: slots),
      );
      final releaseFull = Completer<void>();
      final started = <String>[];
      final jobs = <Future<void>>[
        for (var i = 0; i < slots; i++)
          scheduler.run(ConstellationDbWorkKind.full, () async {
            started.add('full $i');
            await releaseFull.future;
          }),
      ];
      await _settle();
      jobs.add(
        scheduler.run(ConstellationDbWorkKind.apply, () async {
          started.add('apply');
        }),
      );
      await _settle();
      final startedWhileFullsRun = List<String>.of(started);
      releaseFull.complete();
      await Future.wait(jobs);

      expect(startedWhileFullsRun, contains('apply'));
    });

    test(
      'a queued write is admitted within its queue deadline while FULL reads '
      'outlast the deadline',
      () async {
        const deadline = Duration(milliseconds: 300);
        final scheduler = ConstellationDbScheduler(
          config: const ConstellationDbSchedulerConfig(
            maxConcurrent: slots,
            queueDeadline: deadline,
          ),
        );
        final releaseFull = Completer<void>();
        final fulls = [
          for (var i = 0; i < slots; i++)
            scheduler.run(ConstellationDbWorkKind.full, () async {
              await releaseFull.future;
            }),
        ];
        await _settle();

        final applyStarted = Completer<void>();
        final apply = scheduler.run(ConstellationDbWorkKind.apply, () async {
          applyStarted.complete();
        });
        Object? applyError;
        unawaited(
          apply.then<void>((_) {}, onError: (Object e) => applyError = e),
        );

        final admitted = await applyStarted.future
            .timeout(deadline)
            .then((_) => true, onError: (Object _) => false);
        await Future<void>.delayed(deadline * 2);
        releaseFull.complete();
        await Future.wait(fulls);

        expect(admitted, isTrue, reason: 'write not admitted within deadline');
        expect(applyError, isNull);
      },
    );
  });
}
