import 'dart:async';

/// Unions refresh keys until the next event-loop turn.
///
/// A zero-duration timer lets the current microtask queue drain, including
/// individual hints expanded from one invalidation-service buffer flush. This
/// is a client scheduling boundary, not a server transaction identifier.
///
/// The action receives an immutable snapshot. Requests made once it starts
/// belong to a new batch. Async work launched by the action is owned by the
/// caller: this helper neither awaits it nor serializes in-flight reads.
class BurstCoalescer<K> {
  BurstCoalescer(this._action);

  final void Function(Set<K>) _action;
  final _pending = <K>{};
  Timer? _timer;
  bool _disposed = false;

  /// Adds [key] to the next batch; duplicate keys are delivered once.
  /// Requests after [dispose] are ignored.
  void request(K key) {
    if (_disposed) return;
    _pending.add(key);
    _timer ??= Timer(Duration.zero, _flush);
  }

  void _flush() {
    _timer = null;
    final keys = Set<K>.unmodifiable(_pending);
    _pending.clear();
    _action(keys);
  }

  /// Cancels a pending batch. Already-started actions remain caller-owned.
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}
