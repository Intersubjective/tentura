abstract interface class EmailDiscoverabilityPort {
  /// Reads the account's setting. Accounts that have never set it read ON.
  Future<bool> getForAccount(String userId);

  /// Persists an explicit choice and returns the stored value.
  Future<bool> setForAccount({required String userId, required bool enabled});
}
