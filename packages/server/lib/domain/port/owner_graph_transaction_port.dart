/// The owners whose graph the caller may write within this callback.
abstract interface class OwnerGraphScope {
  Set<String> get ownerIds;
}

abstract interface class OwnerGraphTransactionPort {
  /// Runs a mutation after locking all requested owners in ascending order.
  ///
  /// Retries the whole callback after a transient transaction conflict. A
  /// nested call can join with the same actor and a subset of the held owners.
  Future<T> run<T>(
    Set<String> ownerIds,
    String actorUserId,
    Future<T> Function(OwnerGraphScope scope) body,
  );

  /// Locks one owner before reading from a repeatable-read snapshot.
  ///
  /// If the lock was held, the callback runs using a fresh snapshot.
  Future<T> runRepeatableRead<T>(
    String ownerId,
    String actorUserId,
    Future<T> Function(OwnerGraphScope scope) body, {
    int maxAttempts = 3,
  });
}
