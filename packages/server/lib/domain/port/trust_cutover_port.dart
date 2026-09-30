abstract interface class TrustCutoverPort {
  Future<bool> isDone();

  /// Returns the fencing token, or null when another owner holds the lease
  /// (or the cutover is already done).
  Future<int?> acquire(String owner);

  /// Extends the lease; false when [token] is no longer the current one.
  Future<bool> renew(int token);

  /// Every positive vote as `(subject, object)`, ordered.
  Future<List<(String, String)>> votePairs();

  /// Projects [pairs] onto `user_trust_edge`; throws on a stale [token].
  Future<void> projectPairs(int token, List<(String, String)> pairs);

  /// `mr_reset()`; throws on a stale [token].
  Future<void> reset(int token);

  /// `meritrank_init()`; throws on a stale [token].
  Future<void> init(int token);

  /// `mr_sync()`; throws on a stale [token].
  Future<void> sync(int token);

  /// One transaction; no-op when [token] is no longer the current lease.
  Future<void> finish(int token);
}
