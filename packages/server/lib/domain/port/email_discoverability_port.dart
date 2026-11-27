typedef ContactCheckAnswer = ({bool alreadyOnTentura, bool reachedDailyLimit});

abstract interface class EmailDiscoverabilityPort {
  /// Reads the account's setting. Accounts that have never set it read ON.
  Future<bool> getForAccount(String userId);

  /// Persists an explicit choice and returns the stored value.
  Future<bool> setForAccount({required String userId, required bool enabled});

  /// Charges one check for a match or miss. Returns null at the daily limit.
  /// Joins an existing mutation for the caller when part of an import.
  Future<ContactCheckAnswer?> checkEmail(
    String callerId,
    String normalizedEmail,
  );
}
