import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'boot_step.dart';

export 'boot_step.dart';

/// Longest a startup may take before the app gives up and shows the
/// startup-failure screen. Generous: the auth bootstrap alone may take 10 s
/// on a bad network.
const kBootTimeout = Duration(seconds: 60);

typedef BootFailureReporter = void Function(Object error, StackTrace stack);

/// Runs [configure] (dependency setup) and then [afterConfigure].
///
/// Returns `false` — after reporting the error — when either throws or
/// [configure] takes longer than [timeout]. Before #674 such a failure
/// escaped `App.runner` and left the native splash up forever.
Future<bool> bootDependencies({
  required Future<Object?> Function() configure,
  void Function()? afterConfigure,
  Duration timeout = kBootTimeout,
  BootFailureReporter report = reportBootFailure,
}) async {
  final pendingSteps = <String>[];
  try {
    await runWithBootSteps(configure, pendingSteps).timeout(
      timeout,
      onTimeout: () =>
          throw BootTimeoutException(timeout, List.of(pendingSteps)),
    );
    afterConfigure?.call();
    return true;
  } on Object catch (error, stackTrace) {
    report(error, stackTrace);
    return false;
  }
}

/// Logs a startup failure and sends it to Sentry (a no-op without a DSN).
void reportBootFailure(Object error, StackTrace stackTrace) {
  debugPrint('Startup failed: $error');
  unawaited(
    Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) async {
        for (final tag in bootFailureTags(error).entries) {
          await scope.setTag(tag.key, tag.value);
        }
      },
    ),
  );
}

/// The Sentry tags of a startup failure: `boot_step` names the step that
/// hung on a boot timeout (#878).
@visibleForTesting
Map<String, String> bootFailureTags(Object error) => {
  'boot_failure': 'true',
  if (error is BootTimeoutException && error.pendingSteps.isNotEmpty)
    'boot_step': error.pendingSteps.last,
};
