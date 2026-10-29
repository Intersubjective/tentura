import 'dart:async';

/// Unions refresh keys over one server change's hint burst.
///
/// One server change reaches an open client as several hints spread over
/// about two seconds, in separate InvalidationService flushes (100 ms buffer,
/// 16 ms for room messages): a status change sends beacon, hierarchy,
/// activity, room line and notification hints; a withdrawal sends offer, room
/// line, activity, participant, hierarchy and notification hints. There is no
/// server transaction id to group them by (owner D1: client-only), so a batch
/// is a fixed [window] from its first request.
///
/// The window is not reset by later requests. A quiet-gap debounce cannot
/// merge reliably: a surface may hear only the first and the last hint of a
/// burst, so its gap can be the whole spread. Not resetting is also the cap:
/// no refresh waits longer than [window], however many hints keep arriving.
/// 2.5 s spans the observed ~2 s spread plus one flush.
///
/// The action receives an immutable snapshot. Requests made once it starts
/// belong to a new batch. Async work launched by the action is owned by the
/// caller: this helper neither awaits it nor serializes in-flight reads.
class BurstCoalescer<K> {
  BurstCoalescer(this._action);

  static const window = Duration(milliseconds: 2500);

  final void Function(Set<K>) _action;
  final _pending = <K>{};
  Timer? _timer;
  bool _disposed = false;

  /// Adds [key] to the next batch; duplicate keys are delivered once.
  /// Requests after [dispose] are ignored.
  void request(K key) {
    if (_disposed) return;
    _pending.add(key);
    _timer ??= Timer(window, _flush);
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
