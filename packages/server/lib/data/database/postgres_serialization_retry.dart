import 'package:postgres/postgres.dart' show ServerException;

/// Retries [action] once after PostgreSQL deadlock (`40P01`) or serialization
/// failure (`40001`). The failed attempt must run inside a transaction that
/// fully rolls back before the retry (caller's responsibility).
Future<T> withPostgresDeadlockOrSerializationRetry<T>(
  Future<T> Function() action, {
  int maxRetries = 1,
  bool Function(Object error)? isRetryable,
}) async {
  final retryable =
      isRetryable ?? isPostgresDeadlockOrSerializationFailure;
  var attempts = 0;
  while (true) {
    attempts++;
    try {
      return await action();
    } on Object catch (error) {
      if (attempts > maxRetries || !retryable(error)) {
        rethrow;
      }
    }
  }
}

bool isPostgresDeadlockOrSerializationFailure(Object error) {
  if (error is ServerException) {
    final code = error.code;
    return code == '40P01' || code == '40001';
  }
  return false;
}
