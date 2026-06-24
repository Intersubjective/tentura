import 'dart:async';

import 'package:sentry/sentry.dart';

import 'package:tentura_server/env.dart';

import 'sentry_benign_filter.dart';
import 'sentry_event_scrub.dart';
import 'sentry_log_bridge.dart';

Future<void> initSentry({
  required Env env,
  required FutureOr<void> Function() appRunner,
}) async {
  if (!env.isSentryEnabled) {
    configureServerLogSink(sentryEnabled: false);
    await appRunner();
    return;
  }

  await Sentry.init(
    (options) {
      options
        ..dsn = env.sentryDsn
        ..environment = env.environment
        ..sendDefaultPii = true
        ..tracesSampleRate = env.sentryTracesSampleRate
        ..debug = env.isDebugModeOn
        ..ignoreErrors = [
          'SocketException',
        ];
      if (env.sentryRelease.isNotEmpty) {
        options.release = env.sentryRelease;
      }
      if (env.sentryDist.isNotEmpty) {
        options.dist = env.sentryDist;
      }
      options.beforeSend = scrubAndFilterSentryEvent;
    },
    appRunner: () async {
      configureServerLogSink(sentryEnabled: true);
      await appRunner();
    },
    runZonedGuardedOnError: _onZoneError,
  );
}

void _onZoneError(Object error, StackTrace stackTrace) {
  // ignore: avoid_print
  print(error);
  // ignore: avoid_print
  print(stackTrace);
  if (isBenignServerThrowable(error)) {
    return;
  }
  unawaited(Sentry.captureException(error, stackTrace: stackTrace));
}
