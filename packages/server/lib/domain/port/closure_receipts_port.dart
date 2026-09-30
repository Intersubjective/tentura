abstract interface class ClosureReceiptsPort {
  Future<void> opened(String beaconId, int epoch);

  Future<void> finalized(String beaconId, int epoch);

  Future<void> cancelled(String beaconId, int epoch);
}

/// Side-effect-free receipts for callers that do not write outbox rows; the
/// production binding is `ClosureReceiptsRepository`.
class NoopClosureReceipts implements ClosureReceiptsPort {
  const NoopClosureReceipts();

  @override
  Future<void> opened(String beaconId, int epoch) async {}

  @override
  Future<void> finalized(String beaconId, int epoch) async {}

  @override
  Future<void> cancelled(String beaconId, int epoch) async {}
}
