import 'package:sentry_flutter/sentry_flutter.dart';

bool isValidClientAuthAttemptId(String? id) {
  if (id == null || id.isEmpty) return false;
  if (id.length < 8 || id.length > 64) return false;
  return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);
}

Future<void> tagClientAuthAttempt({
  String? authAttemptId,
  required String authMethod,
}) async {
  if (!isValidClientAuthAttemptId(authAttemptId)) return;
  await Sentry.configureScope((scope) {
    scope.setTag('auth_attempt_id', authAttemptId!);
    scope.setTag('auth_method', authMethod);
  });
}

Future<void> emitClientAuthOutcome(
  String event, {
  required String authOutcome,
  String? authAttemptId,
  required String authMethod,
}) async {
  await tagClientAuthAttempt(
    authAttemptId: authAttemptId,
    authMethod: authMethod,
  );
  await Sentry.captureMessage(
    'auth:$event',
    withScope: (scope) {
      scope.setTag('auth_outcome', authOutcome);
      scope.setTag('auth_method', authMethod);
      if (isValidClientAuthAttemptId(authAttemptId)) {
        scope.setTag('auth_attempt_id', authAttemptId!);
      }
    },
  );
}

Future<void> captureSeedRecoveryFailed({
  required String authOutcome,
  String? authAttemptId,
  Object? error,
  StackTrace? stackTrace,
}) async {
  await tagClientAuthAttempt(authAttemptId: authAttemptId, authMethod: 'seed');
  await emitClientAuthOutcome(
    'seed_recovery_failed',
    authOutcome: authOutcome,
    authAttemptId: authAttemptId,
    authMethod: 'seed',
  );
  if (error != null) {
    await Sentry.captureException(
      error,
      stackTrace: stackTrace,
      withScope: (scope) {
        scope.setTag('auth_method', 'seed');
        scope.setTag('auth_outcome', authOutcome);
        if (isValidClientAuthAttemptId(authAttemptId)) {
          scope.setTag('auth_attempt_id', authAttemptId!);
        }
      },
    );
  }
}
