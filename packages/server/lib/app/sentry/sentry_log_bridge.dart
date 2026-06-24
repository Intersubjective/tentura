import 'dart:async';

import 'package:logging/logging.dart';
import 'package:sentry/sentry.dart';

import 'sentry_benign_filter.dart';

/// Routes [Logger.root] records to stdout and optionally to Sentry.
void configureServerLogSink({required bool sentryEnabled}) {
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('${record.level.name}: ${record.loggerName}: ${record.message}');

    if (!sentryEnabled) {
      return;
    }

    if (record.level >= Level.SEVERE) {
      if (isBenignSentryLogRecord(record)) {
        return;
      }
      final error = record.error;
      if (error != null) {
        unawaited(
          Sentry.captureException(error, stackTrace: record.stackTrace),
        );
      } else {
        unawaited(
          Sentry.captureMessage(
            record.message,
            level: SentryLevel.error,
          ),
        );
      }
      return;
    }

    if (record.level == Level.INFO || record.level == Level.WARNING) {
      unawaited(
        Sentry.addBreadcrumb(
          Breadcrumb(
            message: record.message,
            level: record.level == Level.WARNING
                ? SentryLevel.warning
                : SentryLevel.info,
            category: record.loggerName,
          ),
        ),
      );
    }
  });
}
