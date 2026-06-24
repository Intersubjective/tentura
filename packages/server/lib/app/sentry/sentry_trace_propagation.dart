import 'package:sentry/sentry.dart';

/// Applies inbound distributed-tracing headers to a request-scoped [Hub].
///
/// [SentryTransactionContext.fromSentryTrace] alone is not enough: the SDK
/// overwrites the transaction trace id from [Scope.propagationContext], so the
/// propagation context must be seeded first.
void applyIncomingTraceToHub(
  Hub hub,
  SentryTraceHeader? traceHeader,
  SentryBaggage? baggage,
) {
  if (traceHeader == null) {
    return;
  }
  final propagation = hub.scope.propagationContext;
  propagation.traceId = traceHeader.traceId;
  propagation.baggage = baggage;
  if (traceHeader.sampled != null) {
    propagation.applySamplingDecision(traceHeader.sampled!);
  }
  final sampleRand = baggage?.getSampleRand();
  if (sampleRand != null) {
    propagation.sampleRand = sampleRand;
  }
}

SentryTransactionContext buildHttpServerTransactionContext({
  required Hub hub,
  required String transactionName,
  SentryTraceHeader? traceHeader,
  SentryBaggage? baggage,
}) {
  if (traceHeader == null) {
    return SentryTransactionContext(transactionName, 'http.server');
  }
  return SentryTransactionContext.fromSentryTrace(
    transactionName,
    'http.server',
    traceHeader,
    baggage: baggage,
    options: hub.options,
  );
}

SentryTraceHeader? parseSentryTraceHeader(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  try {
    return SentryTraceHeader.fromTraceHeader(raw);
  } on InvalidSentryTraceHeaderException {
    return null;
  }
}

SentryBaggage? parseSentryBaggageHeader(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return SentryBaggage.fromHeader(raw);
}
