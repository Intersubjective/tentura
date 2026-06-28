import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'sentry_benign_filter.dart';

/// Reports a user-facing error to Sentry when it is not an expected/benign
/// failure (validation, connectivity, session loss, etc.).
void reportUserFacingError(
  Object error, {
  StackTrace? stackTrace,
}) {
  if (isBenignSentryThrowable(error)) {
    return;
  }
  unawaited(
    Sentry.captureException(error, stackTrace: stackTrace),
  );
}
