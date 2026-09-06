/// Closed set of safe error codes persisted on hierarchy delivery rows.
///
/// Never store raw exception text — it may contain unexpected source content.
abstract final class BeaconHierarchyDeliverySafeError {
  static const destinationMissing = 'destination_missing';
  static const noticeInsertFailed = 'notice_insert_failed';
  static const attentionDispatchFailed = 'attention_dispatch_failed';
  static const transactionFailed = 'transaction_failed';
  static const unknown = 'unknown';

  static const all = {
    destinationMissing,
    noticeInsertFailed,
    attentionDispatchFailed,
    transactionFailed,
    unknown,
  };

  /// Rows with at least this many recorded attempts stop ordinary due selection.
  static const poisonAttemptThreshold = 10;

  static const initialRetryDelaySeconds = 5;
  static const maxRetryDelaySeconds = 3600;

  static Duration retryDelayForAttemptCount(int attemptCount) {
    if (attemptCount <= 0) {
      return const Duration(seconds: initialRetryDelaySeconds);
    }
    final exponent = attemptCount - 1;
    final multiplier = 1 << exponent.clamp(0, 20);
    final seconds = (initialRetryDelaySeconds * multiplier).clamp(
      initialRetryDelaySeconds,
      maxRetryDelaySeconds,
    );
    return Duration(seconds: seconds);
  }

  static String classify(Object error) {
    final type = error.runtimeType.toString();
    if (type.contains('NoticeInsert')) {
      return noticeInsertFailed;
    }
    if (type.contains('AttentionDispatch')) {
      return attentionDispatchFailed;
    }
    if (type.contains('Postgres') || type.contains('Sqlite')) {
      return transactionFailed;
    }
    return unknown;
  }
}
