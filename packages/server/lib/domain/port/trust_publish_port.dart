/// One queued trust edge to publish to MeritRank; [target] 0 means delete.
class PublishRow {
  const PublishRow(this.subject, this.object, this.target);

  final String subject;
  final String object;
  final double target;
}

abstract interface class TrustPublishPort {
  /// Returns the fencing token, or null when another owner holds the lease.
  Future<int?> acquireLease(String owner);

  Future<bool> leaseValid(int token);

  Future<List<PublishRow>> readBatch(int limit);

  /// `mr_put_edge` / `mr_delete_edge` (when target is 0).
  Future<void> publish(PublishRow row);

  /// `mr_sync()` barrier.
  Future<void> sync();

  /// One transaction; no-op when [token] is no longer the valid lease.
  Future<void> ack(int token, List<PublishRow> rows);

  Future<void> fail(List<PublishRow> rows, String error);

  Future<bool> cutoverPending();
}
