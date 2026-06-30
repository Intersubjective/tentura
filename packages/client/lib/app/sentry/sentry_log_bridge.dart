import 'dart:async';

import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

/// Routes [Logger.root] records to Sentry breadcrumbs when the SDK is initialized.
void configureSentryLogBridge() {
  Logger.root.onRecord.listen((record) {
    final level = _breadcrumbLevelFor(record.level);
    if (level == null) {
      return;
    }

    final error = record.error;
    unawaited(
      Sentry.addBreadcrumb(
        Breadcrumb(
          message: error == null ? record.message : '${record.message}: $error',
          level: level,
          category: record.loggerName,
        ),
      ),
    );
  });
}

SentryLevel? _breadcrumbLevelFor(Level level) {
  if (level >= Level.SEVERE) {
    return SentryLevel.error;
  }
  if (level == Level.WARNING) {
    return SentryLevel.warning;
  }
  if (level == Level.INFO) {
    return SentryLevel.info;
  }
  return null;
}
