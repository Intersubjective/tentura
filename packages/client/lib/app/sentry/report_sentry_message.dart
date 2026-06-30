import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'sentry_benign_filter.dart';

/// Reports an intentional message-only issue to Sentry.
///
/// Use this for diagnostics that are not represented by a throwable. Most
/// exception paths should use `reportUserFacingError` instead.
void reportSentryMessage(
  String message, {
  SentryLevel level = SentryLevel.error,
}) {
  if (isBenignSentryExceptionText(message)) {
    return;
  }
  unawaited(
    Sentry.captureMessage(
      message,
      level: level,
    ),
  );
}
