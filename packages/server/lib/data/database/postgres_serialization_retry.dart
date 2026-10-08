import 'dart:math' show Random;

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
  if (error is PostgresSnapshotUnavailableException) return true;
  if (error is ServerException) {
    final code = error.code;
    return code == '40P01' || code == '40001';
  }
  return false;
}

/// A snapshot dependency failed transiently; retry the entire transaction.
class PostgresSnapshotUnavailableException implements Exception {
  const PostgresSnapshotUnavailableException(this.cause);

  final Object cause;

  @override
  String toString() => 'PostgresSnapshotUnavailableException: $cause';
}

/// Thrown when [withPostgresBoundedRetry] runs out of its end-to-end time
/// budget before an attempt succeeds.
class PostgresRetryDeadlineExceededException implements Exception {
  const PostgresRetryDeadlineExceededException(this.deadline, this.cause);

  final Duration deadline;
  final Object? cause;

  @override
  String toString() =>
      'PostgresRetryDeadlineExceededException: deadline $deadline exceeded'
      '${cause == null ? '' : ' (last error: $cause)'}';
}

/// Runs [action] up to [maxAttempts] times, sleeping a jittered backoff
/// between attempts after a deadlock/serialization failure. [action] must own
/// (and fully roll back) its transaction, so the sleep holds no connection.
/// Aborts with [PostgresRetryDeadlineExceededException] once [deadline] has
/// elapsed since the first attempt started.
Future<T> withPostgresBoundedRetry<T>(
  Future<T> Function() action, {
  int maxAttempts = 3,
  Duration deadline = const Duration(seconds: 5),
  Duration baseBackoff = const Duration(milliseconds: 20),
  Future<void> Function(Duration)? sleep,
  Random? random,
}) async {
  final doSleep = sleep ?? Future<void>.delayed;
  final rng = random ?? Random();
  final clock = Stopwatch()..start();
  var attempts = 0;
  while (true) {
    attempts++;
    try {
      return await action();
    } on Object catch (error) {
      if (!isPostgresDeadlockOrSerializationFailure(error)) rethrow;
      if (clock.elapsed >= deadline) {
        throw PostgresRetryDeadlineExceededException(deadline, error);
      }
      if (attempts >= maxAttempts) rethrow;
      final ceiling = baseBackoff.inMilliseconds * (1 << (attempts - 1));
      await doSleep(Duration(milliseconds: rng.nextInt(ceiling + 1)));
      if (clock.elapsed >= deadline) {
        throw PostgresRetryDeadlineExceededException(deadline, error);
      }
    }
  }
}
