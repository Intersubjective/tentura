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

void configureSentryOptions(SentryFlutterOptions options) {
  options
    ..dsn = sentryDsn
    ..environment = sentryEnvironment
    ..sendDefaultPii = true
    ..enableLogs = true
    // Sentry's Flutter enricher reads LicenseRegistry to list package names.
    // That loads the web `NOTICES` asset; a failed/transient fetch becomes an
    // uncaught secondary error (TENTURA-CLIENT-2E). Versions are always
    // "unknown" anyway — skip the expensive/fragile package scan.
    ..reportPackages = false
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
    if (isBenignSentryEvent(event, hint)) {
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
