// SentryTracer is @internal but the only route to the tags of a request's
// root span (the DB-pipeline spans inherit its GraphQL operation).
// ignore_for_file: invalid_use_of_internal_member
import 'dart:async';
import 'dart:isolate';

import 'package:sentry/sentry.dart';
// SentryTracer is not exported by package:sentry.
// ignore: implementation_imports
import 'package:sentry/src/sentry_tracer.dart' show SentryTracer;

/// Zone value holding the span new DB-pipeline spans nest under. The request
/// middleware sets it to the request transaction (its hub is a clone, so
/// `Sentry.getSpan()` does not see it); a database transaction narrows it to
/// its own span for everything run inside.
final Object kSentryParentSpanZoneKey = Object();

const _graphqlOperationTag = 'graphql.operation';

/// The span DB-pipeline spans should nest under, if any.
ISentrySpan? currentSentrySpan() =>
    Zone.current[kSentryParentSpanZoneKey] as ISentrySpan? ?? Sentry.getSpan();

String _sentryTag(ISentrySpan span, String key) => switch (span) {
  SentryTracer(:final tags) => tags[key] ?? '',
  SentrySpan(:final tags) => tags[key] ?? '',
  _ => '',
};

/// Name of the isolate running the caller, for the `isolate` span tag.
String get sentryIsolateName =>
    Isolate.current.debugName ?? 'isolate-${identityHashCode(Isolate.current)}';

/// Starts a child span of [currentSentrySpan] tagged with the GraphQL
/// operation of the request and the current isolate, or returns null when no
/// transaction is active.
ISentrySpan? startSentryDbSpan(
  String operation, {
  String? description,
  Map<String, String> tags = const {},
}) {
  final parent = currentSentrySpan();
  if (parent == null) return null;
  final span = parent.startChild(operation, description: description);
  final graphqlOperation = _sentryTag(parent, _graphqlOperationTag);
  if (graphqlOperation.isNotEmpty) {
    span.setTag(_graphqlOperationTag, graphqlOperation);
  }
  span.setTag('isolate', sentryIsolateName);
  tags.forEach(span.setTag);
  return span;
}

/// Finishes [span] with an ok status, or with an error status carrying
/// [error]. Does not wait: the end timestamp is taken synchronously.
Future<void> finishSentryDbSpan(ISentrySpan? span, [Object? error]) {
  if (span == null) return Future.value();
  if (error == null) return span.finish(status: const SpanStatus.ok());
  span.throwable = error;
  return span.finish(status: const SpanStatus.internalError());
}

/// Plan §8.10 / H7: runs [body] inside a Sentry child span named [operation]
/// when a transaction is active on the current scope, otherwise runs it
/// unchanged. The span is finished with an ok status on success, or an
/// error status carrying the thrown error when [body] throws.
Future<T> sentryDbSpan<T>(
  String operation,
  Future<T> Function(ISentrySpan? span) body,
) async {
  final span = startSentryDbSpan(operation);
  if (span == null) {
    return body(null);
  }
  try {
    final result = await body(span);
    await finishSentryDbSpan(span);
    return result;
  } on Object catch (error) {
    await finishSentryDbSpan(span, error);
    rethrow;
  }
}
