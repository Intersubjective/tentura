import 'package:sentry/sentry.dart';
import 'package:shelf_plus/shelf_plus.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/env.dart';

import 'sentry_benign_filter.dart';
import 'sentry_event_scrub.dart';
import 'sentry_request_context.dart';
import 'sentry_trace_propagation.dart';

const _excludedPathPrefixes = {
  '/health',
  '/graphiql',
  kPathWebSocketEndpoint,
};

Middleware sentryRequestTracing({required Env env}) {
  return (Handler innerHandler) {
    return (Request request) async {
      if (!env.isSentryEnabled || !_shouldTrace(request)) {
        return innerHandler(request);
      }

      final requestHub = Sentry.clone();
      final traceHeader = parseSentryTraceHeader(request.headers['sentry-trace']);
      final baggage = parseSentryBaggageHeader(request.headers['baggage']);
      applyIncomingTraceToHub(requestHub, traceHeader, baggage);

      final txName = '${request.method} ${request.url.path}';
      final txContext = buildHttpServerTransactionContext(
        hub: requestHub,
        transactionName: txName,
        traceHeader: traceHeader,
        baggage: baggage,
      );

      final transaction = requestHub.startTransactionWithContext(
        txContext,
        bindToScope: true,
      );

      final sentryRequest = SentryRequest.fromUri(
        uri: request.requestedUri,
        method: request.method,
        headers: sanitizeHttpHeaders(Map<String, String>.from(request.headers)),
      );

      final clientIp = clientIpFromHeaders(request.headers);
      requestHub.configureScope((scope) {
        scope.addEventProcessor(SentryRequestEventProcessor(sentryRequest));
        if (clientIp != null) {
          scope.setUser(SentryUser(ipAddress: clientIp));
        }
      });

      final sentryContext = SentryRequestContext(
        hub: requestHub,
        transaction: transaction,
        sentryRequest: sentryRequest,
      );

      final enrichedRequest = request.change(context: {
        kSentryRequestContextKey: sentryContext,
      });

      try {
        final response = await innerHandler(enrichedRequest);
        await sentryContext.enrichFromRequest(enrichedRequest);
        transaction.status = statusFromHttpStatusCode(response.statusCode);
        await transaction.finish();
        return response;
      } on Object catch (error, stackTrace) {
        await sentryContext.enrichFromRequest(enrichedRequest);
        transaction
          ..status = SpanStatus.internalError()
          ..throwable = error;
        if (!isBenignServerThrowable(error)) {
          await sentryContext.captureException(error, stackTrace: stackTrace);
        }
        await transaction.finish();
        rethrow;
      }
    };
  };
}

bool _shouldTrace(Request request) {
  final path = request.url.path;
  if (_excludedPathPrefixes.contains(path)) {
    return false;
  }
  return true;
}

SpanStatus statusFromHttpStatusCode(int statusCode) {
  if (statusCode >= 500) {
    return SpanStatus.internalError();
  }
  if (statusCode >= 400) {
    return SpanStatus.invalidArgument();
  }
  return SpanStatus.ok();
}
