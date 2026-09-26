import 'package:sentry/sentry.dart';

/// Plan §8.10 / H7: runs [body] inside a Sentry child span named [operation]
/// when a transaction is active on the current scope, otherwise runs it
/// unchanged. The span is finished with an ok status on success, or an
/// error status carrying the thrown error when [body] throws.
Future<T> sentryDbSpan<T>(
  String operation,
  Future<T> Function(ISentrySpan? span) body,
) async {
  final parent = Sentry.getSpan();
  if (parent == null) {
    return body(null);
  }
  final span = parent.startChild(operation);
  try {
    final result = await body(span);
    await span.finish(status: const SpanStatus.ok());
    return result;
  } on Object catch (error) {
    span.throwable = error;
    await span.finish(status: const SpanStatus.internalError());
    rethrow;
  }
}
