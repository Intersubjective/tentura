/// A private object cleanup job and its attempt count after claiming.
final class PrivateObjectGcLease {
  const PrivateObjectGcLease({
    required this.objectKey,
    required this.attempts,
  });

  final String objectKey;
  final int attempts;
}

abstract interface class PrivateObjectGcPort {
  Future<List<PrivateObjectGcLease>> claim({
    required String leaseOwner,
    required DateTime now,
    int limit = 32,
  });

  /// Acknowledges the lease and removes the stored object if unreferenced.
  Future<void> collect({
    required String objectKey,
    required String leaseOwner,
  });

  Future<bool> complete({
    required String objectKey,
    required String leaseOwner,
  });

  Future<bool> fail({
    required String objectKey,
    required String leaseOwner,
    required DateTime retryAt,
    required String error,
  });
}
