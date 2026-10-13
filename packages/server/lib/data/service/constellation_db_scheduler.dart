import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/port/constellation_db_admission_port.dart';
import 'package:tentura_server/env.dart';

import '../database/main_db_pool.dart';
import 'main_db_scope_admission.dart';

export 'package:tentura_server/domain/port/constellation_db_admission_port.dart'
    show ConstellationDbWorkKind;

class ConstellationDbSchedulerConfig {
  const ConstellationDbSchedulerConfig({
    this.maxConcurrent = 2,
    this.maxQueued = 32,
    this.queueDeadline = const Duration(seconds: 1),
    this.reservedRefreshShare = 0.3,
    this.retryAfter = const Duration(seconds: 2),
  });

  factory ConstellationDbSchedulerConfig.fromEnv(Env env) =>
      ConstellationDbSchedulerConfig(
        maxConcurrent: env.constellationDbMaxConcurrent,
        reservedRefreshShare: env.constellationDbRefreshShare,
      );

  final int maxConcurrent;

  /// Bounds waiting items only; running work does not count.
  final int maxQueued;
  final Duration queueDeadline;
  final double reservedRefreshShare;
  final Duration retryAfter;
}

class ConstellationDbSchedulerStats {
  int completedFull = 0;
  Duration maxQueueAge = Duration.zero;
  Duration maxFullStaleness = Duration.zero;
}

@LazySingleton(as: ConstellationDbAdmissionPort)
class ConstellationDbScheduler implements ConstellationDbAdmissionPort {
  ConstellationDbScheduler({
    this.config = const ConstellationDbSchedulerConfig(),
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now,
       _admission = MainDbScopeAdmission(
         maxConcurrent: config.maxConcurrent,
         maxHeavy: config.maxConcurrent,
         reservedRefreshShare: config.reservedRefreshShare,
         reservedInteractiveSlot: true,
         maxQueued: config.maxQueued,
         interactiveDeadline: config.queueDeadline,
         fullDeadline: config.queueDeadline,
         retryAfter: config.retryAfter,
       );

  ConstellationDbScheduler.fromEnv(Env env)
    : config = ConstellationDbSchedulerConfig.fromEnv(env),
      _now = DateTime.now,
      _admission = MainDbScopeAdmission(
        maxConcurrent: env.pgPoolSettings.maxConnectionCount ?? 4,
      );

  @FactoryMethod()
  ConstellationDbScheduler.injected(MainDbPool pool)
    : config = ConstellationDbSchedulerConfig(
        maxConcurrent: pool.admission.maxConcurrent,
      ),
      _now = DateTime.now,
      _admission = pool.admission;

  final ConstellationDbSchedulerConfig config;
  final DateTime Function() _now;
  final MainDbScopeAdmission _admission;
  final stats = ConstellationDbSchedulerStats();

  int get queued => _admission.queued;
  int get running => _admission.running;

  @override
  Future<T> run<T>(ConstellationDbWorkKind kind, Future<T> Function() body) {
    final enqueuedAt = _now();
    return _admission.run(
      () async {
        final queueAge = _now().difference(enqueuedAt);
        if (queueAge > stats.maxQueueAge) stats.maxQueueAge = queueAge;
        final value = await body();
        if (kind == ConstellationDbWorkKind.full) {
          stats.completedFull++;
          final staleness = _now().difference(enqueuedAt);
          if (staleness > stats.maxFullStaleness) {
            stats.maxFullStaleness = staleness;
          }
        }
        return value;
      },
      kind: switch (kind) {
        ConstellationDbWorkKind.apply => MainDbWorkKind.interactive,
        ConstellationDbWorkKind.anchors => MainDbWorkKind.refresh,
        ConstellationDbWorkKind.full => MainDbWorkKind.full,
      },
      actorUserId: MainDbWorkContext.current?.actorUserId,
      workClass: kind.name,
    );
  }
}
