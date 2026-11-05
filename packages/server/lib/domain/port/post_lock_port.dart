/// Serializes Post mutations and deliveries. Callers re-check everything
/// mutable after acquiring the locks.
abstract interface class PostLockPort {
  /// Hierarchy → Post advisory lock → Post row, for hierarchy mutations.
  Future<void> lockForPostMutation(String beaconId);

  /// Sender block barrier (shared) → Post advisory lock → Post row.
  /// Delivery must never request the hierarchy lock after taking these locks.
  Future<void> lockForPostDelivery(String beaconId, {required String senderId});
}
