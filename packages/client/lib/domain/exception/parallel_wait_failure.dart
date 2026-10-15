import 'dart:async';

import 'generic_exception.dart';

/// The failures behind a [ParallelWaitError] (the successful branches are
/// skipped), or `null` when [error] is not one or has an unrecognised shape.
///
/// `.wait` on a list reports a list of branch results; on a record it reports
/// a record of the same arity. Records cannot be iterated generically, hence
/// the explicit arities.
List<Object>? parallelWaitCauses(Object error) {
  if (error is! ParallelWaitError) {
    return null;
  }
  final results = switch (error.errors) {
    final List<Object?> list => list,
    (final a, final b) => [a, b],
    (final a, final b, final c) => [a, b, c],
    (final a, final b, final c, final d) => [a, b, c, d],
    (final a, final b, final c, final d, final e) => [a, b, c, d, e],
    _ => null,
  };
  return results?.whereType<AsyncError>().map((e) => e.error).toList();
}

/// One [RemoteApiRetryLaterException] that waits for the longest of [causes]
/// hints, or `null` unless [causes] is non-empty and every one is retry-later.
RemoteApiRetryLaterException? combinedRetryLater(Iterable<Object> causes) {
  final hints = causes.whereType<RemoteApiRetryLaterException>().toList();
  if (hints.isEmpty || hints.length != causes.length) {
    return null;
  }
  return hints.reduce((a, b) => a.retryAfter >= b.retryAfter ? a : b);
}

/// A [ParallelWaitError] whose failures are all retry-later reads as a single
/// [RemoteApiRetryLaterException]; any other [error] is returned unchanged.
Object unwrapRetryLater(Object error) =>
    combinedRetryLater(parallelWaitCauses(error) ?? const []) ?? error;
