import 'package:sentry_flutter/sentry_flutter.dart';

import 'package:tentura/consts.dart';

import 'sentry_benign_filter.dart';

const sentryDsn = String.fromEnvironment('SENTRY_DSN');
const sentryEnvironment = String.fromEnvironment(
  'SENTRY_ENVIRONMENT',
  defaultValue: 'development',
);
const sentryRelease = String.fromEnvironment('SENTRY_RELEASE');
const sentryDist = String.fromEnvironment('SENTRY_DIST');

bool _isBenignSentryEvent(SentryEvent event, Hint hint) {
  final synthetic = hint.get(TypeCheckHint.syntheticException);
  if (isBenignSentryThrowable(synthetic)) {
    return true;
  }

  final message = event.message?.formatted ?? '';
  if (isBenignSentryExceptionText(message)) {
    return true;
  }

  final exceptions = event.exceptions;
  if (exceptions == null) {
    return false;
  }

  for (final ex in exceptions) {
    final type = ex.type ?? '';
    if (type.contains('ConnectionUplinkException') ||
        type.contains('AuthSessionLostException') ||
        type.contains('AuthenticationNoKeyException')) {
      return true;
    }
    final value = ex.value ?? '';
    if (isBenignSentryExceptionText(value)) {
      return true;
    }
    if (ex.type == 'AbortError' &&
        value.toLowerCase().contains('serviceworker')) {
      return true;
    }
  }
  return false;
}

void configureSentryOptions(SentryFlutterOptions options) {
  options
    ..dsn = sentryDsn
    ..environment = sentryEnvironment
    ..sendDefaultPii = true
    ..tracesSampleRate = 1.0
    ..captureFailedRequests = false
    ..debug = false
    ..ignoreErrors = [
      'SocketException',
    ];

  if (sentryRelease.isNotEmpty) {
    options.release = sentryRelease;
  }
  if (sentryDist.isNotEmpty) {
    options.dist = sentryDist;
  }

  _configureTracePropagation(options);

  options.beforeSend = (event, hint) {
    if (_isBenignSentryEvent(event, hint)) {
      return null;
    }
    return event;
  };
}

void _configureTracePropagation(SentryFlutterOptions options) {
  if (kServerName.isEmpty) {
    return;
  }
  final origin = Uri.parse(kServerName).origin;
  options.tracePropagationTargets
    ..clear()
    ..addAll([
      origin,
      '$origin$kPathGraphQLEndpoint',
      '$origin$kPathGraphQLEndpointV2',
    ]);
}
