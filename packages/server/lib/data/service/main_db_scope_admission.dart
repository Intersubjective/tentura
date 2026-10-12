import 'dart:async';
import 'dart:collection';

import 'package:sentry/sentry.dart';
import 'package:tentura_server/app/sentry/sentry_db_span.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

enum MainDbWorkKind { interactive, full }

/// One waiting queue for the pool. Admission precedes connection acquisition.
final class MainDbScopeAdmission {
  MainDbScopeAdmission({
    required this.maxConcurrent,
    this.maxQueued = 32,
    this.maxQueuedPerActor = 4,
    this.maxHeavy = 1,
    this.interactiveDeadline = const Duration(milliseconds: 250),
    this.fullDeadline = const Duration(seconds: 1),
    this.retryAfter = const Duration(seconds: 2),
  });

  final int maxConcurrent;
  final int maxQueued;
  final int maxQueuedPerActor;
  final int maxHeavy;
  final Duration interactiveDeadline;
  final Duration fullDeadline;
  final Duration retryAfter;
  final _waiting = Queue<_AdmissionWaiter>();
  final _clock = Stopwatch()..start();
  final _actors = <String, int>{};
  int _running = 0;
  int _heavy = 0;
  bool _closed = false;

  int get queued => _waiting.length;
  int get running => _running;

  Future<T> run<T>(
    Future<T> Function() body, {
    MainDbWorkKind kind = MainDbWorkKind.interactive,
    String? actorUserId,
  }) {
    final actor = actorUserId?.trim();
    if (_closed ||
        _waiting.length >= maxQueued ||
        (actor != null && (_actors[actor] ?? 0) >= maxQueuedPerActor)) {
      return Future.error(_retryLater());
    }
    final result = Completer<T>();
    final budget = kind == MainDbWorkKind.full
        ? fullDeadline
        : interactiveDeadline;
    final waiter = _AdmissionWaiter(kind, actor, _clock.elapsed + budget);
    final zone = Zone.current;
    waiter
      ..waitSpan = startSentryDbSpan(
        'db.admission.wait',
        tags: {'work.class': kind.name},
      )
      ..refuse = result.completeError
      ..timer = Timer(budget, () => _expire(waiter))
      ..start = () => zone.run(() async {
        try {
          result.complete(await body());
        } on Object catch (error, stack) {
          result.completeError(error, stack);
        } finally {
          _running--;
          if (kind == MainDbWorkKind.full) _heavy--;
          _pump();
        }
      });
    _waiting.add(waiter);
    if (actor != null) _actors[actor] = (_actors[actor] ?? 0) + 1;
    _pump();
    return result.future;
  }

  void _remove(_AdmissionWaiter waiter) {
    _waiting.remove(waiter);
    waiter.timer?.cancel();
    final actor = waiter.actor;
    if (actor != null) {
      final count = _actors[actor]! - 1;
      if (count == 0) {
        _actors.remove(actor);
      } else {
        _actors[actor] = count;
      }
    }
  }

  void _expire(_AdmissionWaiter waiter) {
    if (!_waiting.contains(waiter)) return;
    _remove(waiter);
    final error = _retryLater();
    unawaited(finishSentryDbSpan(waiter.waitSpan, error));
    waiter.start = null;
    waiter.refuse!(error);
    waiter.refuse = null;
  }

  void _pump() {
    for (final waiter in _waiting.toList()) {
      // Check the deadline here too: a ready slot may precede the timer's turn.
      if (_clock.elapsed >= waiter.deadline) {
        _expire(waiter);
        continue;
      }
      if (_running >= maxConcurrent) break;
      if (waiter.kind == MainDbWorkKind.full && _heavy >= maxHeavy) continue;
      _remove(waiter);
      _running++;
      if (waiter.kind == MainDbWorkKind.full) _heavy++;
      unawaited(finishSentryDbSpan(waiter.waitSpan));
      final start = waiter.start!;
      waiter
        ..start = null
        ..refuse = null;
      // Each body runs in the submitting request's zone.
      scheduleMicrotask(() => unawaited(start()));
    }
  }

  void close() {
    _closed = true;
    _waiting.toList().forEach(_expire);
  }

  ConstellationException _retryLater() => ConstellationException(
    constellationCode: ConstellationExceptionCode.retryLater,
    retryAfter: retryAfter,
  );
}

final class _AdmissionWaiter {
  _AdmissionWaiter(this.kind, this.actor, this.deadline);

  final MainDbWorkKind kind;
  final String? actor;
  final Duration deadline;
  Future<void> Function()? start;
  void Function(Object)? refuse;
  Timer? timer;
  ISentrySpan? waitSpan;
}
