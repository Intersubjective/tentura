/// Per-user sliding-window throttle for fact searches (in-memory, per
/// process).
final class FactSearchRateLimiter {
  FactSearchRateLimiter({required this.max, required this.window});

  final int max;

  final Duration window;

  final _hits = <String, List<DateTime>>{};

  /// How many users still have a search inside the window.
  int get trackedUsers => _hits.length;

  /// Records a search of [userId]; false when [max] searches already fall
  /// inside [window].
  bool tryAcquire(String userId) {
    final now = DateTime.timestamp();
    _hits.removeWhere(
      (_, times) => times.every((t) => now.difference(t) >= window),
    );
    final hits = _hits.putIfAbsent(userId, () => [])
      ..removeWhere((t) => now.difference(t) >= window);
    if (hits.length >= max) return false;
    hits.add(now);
    return true;
  }
}
