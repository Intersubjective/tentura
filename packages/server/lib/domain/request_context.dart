import 'dart:async';

enum RequestOperationClass { auth, interactive, full, upload }

/// One monotonic budget follows authentication, admission, SQL and retries.
final class RequestContext {
  RequestContext({required this.requestId}) {
    _armDeadline();
  }

  static final _zoneKey = Object();
  static RequestContext? get current =>
      Zone.current[_zoneKey] as RequestContext?;

  final String requestId;
  String? actor;
  RequestOperationClass operationClass = RequestOperationClass.interactive;
  final _startedAt = DateTime.now();
  final _clock = Stopwatch()..start();
  final _cancelled = Completer<void>();
  final _listeners = <void Function()>{};
  Duration _budget = const Duration(seconds: 5);
  Timer? _timer;
  late Object _reason;

  DateTime get deadline => _startedAt.add(_budget);
  Duration get remaining => _budget - _clock.elapsed;
  Future<void> get cancellation => _cancelled.future;
  bool get isCancelled => _cancelled.isCompleted;

  Future<T> run<T>(Future<T> Function() action) =>
      runZoned(action, zoneValues: {_zoneKey: this});

  void classify(RequestOperationClass value) {
    operationClass = value;
    _budget = switch (value) {
      RequestOperationClass.auth => const Duration(seconds: 2),
      RequestOperationClass.interactive => const Duration(seconds: 5),
      RequestOperationClass.full => const Duration(seconds: 12),
      RequestOperationClass.upload => const Duration(minutes: 2),
    };
    _armDeadline();
  }

  void _armDeadline() {
    _timer?.cancel();
    if (isCancelled) return;
    if (remaining <= Duration.zero) {
      cancel(TimeoutException('Request deadline exceeded', _budget));
    } else {
      _timer = Timer(
        remaining,
        () => cancel(TimeoutException('Request deadline exceeded', _budget)),
      );
    }
  }

  void check() {
    if (!isCancelled && remaining <= Duration.zero) {
      cancel(TimeoutException('Request deadline exceeded', _budget));
    }
    if (isCancelled) Error.throwWithStackTrace(_reason, StackTrace.current);
  }

  void cancel([Object? reason]) {
    if (isCancelled) return;
    _reason = reason ?? StateError('Request cancelled');
    _timer?.cancel();
    _cancelled.complete();
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  /// Registration is synchronous so disconnect cannot race scope release.
  void Function() onCancel(void Function() listener) {
    if (isCancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
    return () => _listeners.remove(listener);
  }

  void dispose() => _timer?.cancel();
}
