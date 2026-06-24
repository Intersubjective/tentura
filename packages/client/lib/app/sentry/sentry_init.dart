import 'package:sentry_flutter/sentry_flutter.dart';

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

  final exceptions = event.exceptions;
  if (exceptions == null) {
    return false;
  }

  for (final ex in exceptions) {
    final type = ex.type ?? '';
    if (type.contains('ConnectionUplinkException') ||
        type.contains('AuthSessionLostException')) {
      return true;
    }
    final value = ex.value ?? '';
    if (value.toLowerCase().contains('socketexception')) {
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

  options.beforeSend = (event, hint) {
    if (_isBenignSentryEvent(event, hint)) {
      return null;
    }
    return event;
  };
}
