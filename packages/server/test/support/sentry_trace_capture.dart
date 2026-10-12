import 'package:sentry/sentry.dart';

/// Initialises Sentry in-process (no network) and hands back the finished
/// transaction tree of one simulated request, so tests can assert which spans
/// a code path emits.
final class SentryTraceCapture {
  SentryTransaction? _sent;

  Future<void> start() async {
    await Sentry.close();
    _sent = null;
    await Sentry.init((options) {
      options
        ..dsn = 'https://public@o123.ingest.sentry.io/1'
        // Deliberate: rethrow exceptions in user closures during tests.
        // ignore: invalid_use_of_internal_member
        ..automatedTestMode = true
        ..tracesSampleRate = 1.0
        ..beforeSendTransaction = (transaction, hint) {
          _sent = transaction;
          // The assertions use the captured trace without sending it over HTTP.
          return null;
        };
    });
  }

  Future<void> stop() => Sentry.close();

  /// Opens a root transaction bound to the scope, like the request middleware.
  ISentrySpan beginRequest({String? graphqlOperation}) {
    final transaction = Sentry.startTransaction(
      'test-request',
      'http.server',
      bindToScope: true,
    );
    if (graphqlOperation != null) {
      transaction.setTag('graphql.operation', graphqlOperation);
    }
    return transaction;
  }

  /// What Sentry sent for a transaction that code under test finished itself
  /// (e.g. the request-tracing middleware).
  SentryTransaction get sent {
    final sent = _sent;
    if (sent == null) {
      throw StateError('Sentry did not send a finished transaction');
    }
    return sent;
  }

  /// Finishes [request] and returns what Sentry would have sent.
  Future<SentryTransaction> finish(ISentrySpan request) async {
    await request.finish();
    final sent = _sent;
    if (sent == null) {
      throw StateError('Sentry did not send the finished transaction');
    }
    return sent;
  }
}

extension SentryTransactionSpans on SentryTransaction {
  SentrySpan spanWithId(SpanId id) =>
      spans.singleWhere((span) => span.context.spanId == id);

  List<SentrySpan> spansWithOperation(String operation) => [
    for (final span in spans)
      if (span.context.operation == operation) span,
  ];
}

extension SentrySpanTiming on SentrySpan {
  Duration get elapsed => endTimestamp!.difference(startTimestamp);
}

extension SentrySpanOrdering on SentrySpan {
  /// This span finished no later than [other] started.
  bool endsBeforeStartOf(SentrySpan other) =>
      !endTimestamp!.isAfter(other.startTimestamp);

  /// This span lies entirely inside [other].
  bool isWithin(SentrySpan other) =>
      !startTimestamp.isBefore(other.startTimestamp) &&
      !endTimestamp!.isAfter(other.endTimestamp!);
}
