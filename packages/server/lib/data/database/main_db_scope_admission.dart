import 'dart:async';
import 'dart:collection';

import 'package:sentry/sentry.dart';
import 'package:tentura_server/app/sentry/sentry_db_span.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/request_context.dart';

enum MainDbWorkKind { interactive, refresh, full }

/// Admission metadata follows a request or batch loop without leasing a pool
/// connection. Each database scope still acquires and releases independently.
final class MainDbWorkContext {
  const MainDbWorkContext._(this.actorUserId, this.kind);

  static final Object _zoneKey = Object();

  final String? actorUserId;
  final MainDbWorkKind kind;

  static MainDbWorkContext? get current =>
      Zone.current[_zoneKey] as MainDbWorkContext?;

  static Future<T> run<T>(
    Future<T> Function() action, {
    String? actorUserId,
    MainDbWorkKind kind = MainDbWorkKind.interactive,
  }) {
    final actor = actorUserId?.trim();
    return runZoned(
      action,
      zoneValues: {
        _zoneKey: MainDbWorkContext._(
          actor == null || actor.isEmpty ? null : actor,
          kind,
        ),
      },
    );
  }
}

/// One waiting queue for the pool. Admission precedes connection acquisition.
final class MainDbScopeAdmission {
  MainDbScopeAdmission({
    required this.maxConcurrent,
    this.maxQueued = 32,
    this.maxQueuedPerActor = 4,
    this.maxHeavy = 1,
    this.reservedRefreshShare = 0.3,
    this.reservedInteractiveSlot = false,
    this.interactiveDeadline = const Duration(milliseconds: 250),
    this.fullDeadline = const Duration(seconds: 1),
    this.retryAfter = const Duration(seconds: 2),
    this.enforceReentryGuard = true,
  });

  final int maxConcurrent;
  final int maxQueued;
  final int maxQueuedPerActor;
  final int maxHeavy;
  final double reservedRefreshShare;
  // Standalone admission can reserve an extra write slot. Pool-backed scopes
  // always stay within maxConcurrent, which is their connection budget.
  final bool reservedInteractiveSlot;
  final Duration interactiveDeadline;
  final Duration fullDeadline;
  final Duration retryAfter;

  /// Test/debug guard: an admitted body must not take a second slot of this
  /// admission (it would deadlock once the slots are all held by such bodies).
  final bool enforceReentryGuard;
  final Object _slotZoneKey = Object();
  final _waiting = Queue<_AdmissionWaiter>();
  final _clock = Stopwatch()..start();
  final _actors = <String, int>{};
  int _running = 0;
  int _heavy = 0;
  int _interactive = 0;
  double _refreshCredit = 0;
  bool _closed = false;

  int get queued => _waiting.length;
  int get running => _running;

  Future<T> run<T>(
    Future<T> Function() body, {
    MainDbWorkKind kind = MainDbWorkKind.interactive,
    String? actorUserId,
    String? workClass,
  }) {
    final request = RequestContext.current;
    try {
      request?.check();
    } on Object catch (error, stack) {
      return Future.error(error, stack);
    }
    final actor = actorUserId?.trim();
    if (enforceReentryGuard) {
      final held = Zone.current[_slotZoneKey];
      if (held is _HeldSlot && held.active) {
        return Future.error(
          StateError(
            'Main DB admission re-entry: the running body already holds a '
            'slot of this admission and must reuse its connection scope',
          ),
        );
      }
    }
    _pump();
    final startsImmediately = _canStart(kind);
    if (_closed ||
        (!startsImmediately &&
            (_waiting.length >= maxQueued ||
                (actor != null &&
                    (_actors[actor] ?? 0) >= maxQueuedPerActor)))) {
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
        tags: {'work.class': workClass ?? kind.name},
      )
      ..refuse = result.completeError
      ..timer = Timer(budget, () => _expire(waiter))
      ..start = () => zone.run(() async {
        final slot = _HeldSlot();
        try {
          result.complete(
            await (enforceReentryGuard
                ? runZoned(body, zoneValues: {_slotZoneKey: slot})
                : body()),
          );
        } on Object catch (error, stack) {
          result.completeError(error, stack);
        } finally {
          slot.active = false;
          _running--;
          if (kind == MainDbWorkKind.full) _heavy--;
          if (kind == MainDbWorkKind.interactive) _interactive--;
          _pump();
        }
      });
    _waiting.add(waiter);
    if (actor != null) _actors[actor] = (_actors[actor] ?? 0) + 1;
    waiter.cancelRegistration = request?.onCancel(() {
      if (!_waiting.contains(waiter)) return;
      _remove(waiter);
      Object? error;
      try {
        request.check();
      } on Object catch (cancelled) {
        error = cancelled;
      }
      unawaited(finishSentryDbSpan(waiter.waitSpan, error));
      waiter.start = null;
      waiter.refuse!(error!);
      waiter.refuse = null;
      _pump();
    });
    _pump();
    return result.future;
  }

  void _remove(_AdmissionWaiter waiter) {
    _waiting.remove(waiter);
    waiter.timer?.cancel();
    waiter.cancelRegistration?.call();
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
      }
    }
    while (true) {
      final waiter = _pick();
      if (waiter == null) return;
      _remove(waiter);
      _running++;
      if (waiter.kind == MainDbWorkKind.full) _heavy++;
      if (waiter.kind == MainDbWorkKind.interactive) _interactive++;
      unawaited(finishSentryDbSpan(waiter.waitSpan));
      final start = waiter.start!;
      waiter
        ..start = null
        ..refuse = null;
      // Each body runs in the submitting request's zone.
      scheduleMicrotask(() => unawaited(start()));
    }
  }

  bool _canStart(MainDbWorkKind kind) {
    if (kind == MainDbWorkKind.full && _heavy >= maxHeavy) return false;
    return _running < maxConcurrent ||
        (reservedInteractiveSlot &&
            kind == MainDbWorkKind.interactive &&
            _interactive == 0);
  }

  _AdmissionWaiter? _pick() {
    _AdmissionWaiter? interactive;
    _AdmissionWaiter? refresh;
    for (final waiter in _waiting) {
      if (waiter.kind == MainDbWorkKind.interactive) {
        interactive ??= waiter;
      } else if (_canStart(waiter.kind)) {
        refresh ??= waiter;
      }
    }
    if (interactive == null) _refreshCredit = 0;
    final writeOk = interactive != null && _canStart(interactive.kind);
    if (!writeOk && refresh == null) return null;
    if (interactive != null &&
        _waiting.any((w) => w.kind != MainDbWorkKind.interactive)) {
      _refreshCredit += reservedRefreshShare;
      if (refresh != null && _refreshCredit >= 1) {
        _refreshCredit -= 1;
        return refresh;
      }
    }
    return writeOk ? interactive : refresh;
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

final class _HeldSlot {
  bool active = true;
}

final class _AdmissionWaiter {
  _AdmissionWaiter(this.kind, this.actor, this.deadline);

  final MainDbWorkKind kind;
  final String? actor;
  final Duration deadline;
  Future<void> Function()? start;
  void Function(Object)? refuse;
  Timer? timer;
  void Function()? cancelRegistration;
  ISentrySpan? waitSpan;
}
