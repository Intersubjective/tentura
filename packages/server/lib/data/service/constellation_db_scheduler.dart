import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/constellation_db_admission_port.dart';
import 'package:tentura_server/env.dart';

export 'package:tentura_server/domain/port/constellation_db_admission_port.dart'
    show ConstellationDbWorkKind;

class ConstellationDbSchedulerConfig {
  const ConstellationDbSchedulerConfig({
    this.maxConcurrent = 2,
    this.maxQueued = 1000,
    this.queueDeadline = const Duration(seconds: 10),
    this.reservedRefreshShare = 0.3,
    this.retryAfter = const Duration(seconds: 2),
  });

  factory ConstellationDbSchedulerConfig.fromEnv(Env env) =>
      ConstellationDbSchedulerConfig(
        maxConcurrent: min(
          env.pgPoolSettings.maxConnectionCount!,
          env.constellationDbMaxConcurrent,
        ),
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
  }) : _now = now ?? DateTime.now;

  @FactoryMethod()
  ConstellationDbScheduler.fromEnv(Env env)
    : config = ConstellationDbSchedulerConfig.fromEnv(env),
      _now = DateTime.now;

  final ConstellationDbSchedulerConfig config;
  final DateTime Function() _now;
  final stats = ConstellationDbSchedulerStats();

  final _writes = Queue<_Waiter>();
  final _refreshes = Queue<_Waiter>();
  var _running = 0;
  var _refreshCredit = 0.0;

  int get _waiting => _writes.length + _refreshes.length;

  @override
  Future<T> run<T>(
    ConstellationDbWorkKind kind,
    Future<T> Function() body,
  ) {
    if (_running + _waiting >= config.maxConcurrent + config.maxQueued) {
      return Future.error(_retryLater());
    }
    final waiter = _Waiter(kind, _now());
    final result = Completer<T>();
    // Admission happens from whichever body finished last; the body itself
    // must run in its caller's zone (Sentry scope, transaction and actor keys).
    final zone = Zone.current;
    waiter
      ..start = (() => zone.run(() => _execute(waiter, body, result)))
      ..timer = Timer(config.queueDeadline, () {
        if ((waiter.isWrite ? _writes : _refreshes).remove(waiter)) {
          result.completeError(_retryLater());
        }
      });
    (waiter.isWrite ? _writes : _refreshes).add(waiter);
    // Admission is deferred so a body never starts inside the caller's call.
    scheduleMicrotask(_pump);
    return result.future;
  }

  void _pump() {
    while (_running < config.maxConcurrent && _waiting > 0) {
      final queue = _pick();
      final waiter = queue.removeFirst()..timer?.cancel();
      _running++;
      unawaited(waiter.start!());
    }
  }

  Queue<_Waiter> _pick() {
    if (_writes.isEmpty) {
      _refreshCredit = 0;
      return _refreshes;
    }
    if (_refreshes.isEmpty) return _writes;
    _refreshCredit += config.reservedRefreshShare;
    if (_refreshCredit >= 1) {
      _refreshCredit -= 1;
      return _refreshes;
    }
    return _writes;
  }

  Future<void> _execute<T>(
    _Waiter waiter,
    Future<T> Function() body,
    Completer<T> result,
  ) async {
    final queueAge = _now().difference(waiter.enqueuedAt);
    if (queueAge > stats.maxQueueAge) stats.maxQueueAge = queueAge;
    try {
      result.complete(await body());
      if (waiter.kind == ConstellationDbWorkKind.full) {
        stats.completedFull++;
        final staleness = _now().difference(waiter.enqueuedAt);
        if (staleness > stats.maxFullStaleness) {
          stats.maxFullStaleness = staleness;
        }
      }
    } catch (e, st) {
      result.completeError(e, st);
    } finally {
      _running--;
      scheduleMicrotask(_pump);
    }
  }

  ConstellationException _retryLater() => ConstellationException(
    constellationCode: ConstellationExceptionCode.retryLater,
    retryAfter: config.retryAfter,
  );
}

final class _Waiter {
  _Waiter(this.kind, this.enqueuedAt);

  final ConstellationDbWorkKind kind;
  final DateTime enqueuedAt;
  Future<void> Function()? start;
  Timer? timer;

  bool get isWrite => kind == ConstellationDbWorkKind.apply;
}
