import '../exception.dart';

abstract class UploadQuotaRepositoryPort {
  /// Atomically add [bytes] to [userId]'s usage for the current UTC day and
  /// report whether the new daily total stays within [dailyCapBytes].
  ///
  /// Returns `true` when the bytes were reserved (within cap). Returns `false`
  /// when the upload would exceed the cap; in that case no usage is retained
  /// (the speculative increment is rolled back), so a rejected upload never
  /// consumes quota.
  Future<bool> tryReserveDailyBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  });

  /// Total bytes [userId] has uploaded so far during the current UTC day.
  Future<int> usedBytesToday(String userId);
}

extension UploadQuotaReservation on UploadQuotaRepositoryPort {
  Future<void> reserveUploadBytes({
    required String userId,
    required int bytes,
    required int dailyCapBytes,
  }) async {
    if (!await tryReserveDailyBytes(
      userId: userId,
      bytes: bytes,
      dailyCapBytes: dailyCapBytes,
    )) {
      throw const RateLimitedException(
        description: 'Daily upload limit reached, try again tomorrow',
      );
    }
  }
}
