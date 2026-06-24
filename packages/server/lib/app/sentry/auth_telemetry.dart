import 'package:sentry/sentry.dart';
import 'package:shelf_plus/shelf_plus.dart';

import 'sentry_request_context.dart';

/// Opaque correlation id — email tx ids, landing-generated Google/seed ids.
bool isValidAuthAttemptId(String? id) {
  if (id == null || id.isEmpty) return false;
  if (id.length < 8 || id.length > 64) return false;
  return RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id);
}

Hub authTelemetryHub(Request? request) {
  if (request != null) {
    final ctx = SentryRequestContext.from(request);
    if (ctx != null) return ctx.hub;
  }
  return HubAdapter();
}

Future<void> tagAuthAttempt({
  Request? request,
  String? authAttemptId,
  required String authMethod,
}) async {
  if (!isValidAuthAttemptId(authAttemptId)) return;
  final hub = authTelemetryHub(request);
  await hub.configureScope((scope) {
    scope.setTag('auth_attempt_id', authAttemptId!);
    scope.setTag('auth_method', authMethod);
  });
}

Future<void> emitEmailStartOutcome({
  required String authOutcome,
  required String correlationId,
  Request? request,
}) async {
  await emitAuthOutcome(
    'email_start_outcome',
    authOutcome: authOutcome,
    authAttemptId: correlationId,
    authMethod: 'email',
    request: request,
  );
}

Future<void> emitAuthOutcome(
  String event, {
  required String authOutcome,
  String? authAttemptId,
  String? authMethod,
  Request? request,
}) async {
  final hub = authTelemetryHub(request);
  if (authMethod != null) {
    await tagAuthAttempt(
      request: request,
      authAttemptId: authAttemptId,
      authMethod: authMethod,
    );
  }
  await hub.captureMessage(
    'auth:$event',
    withScope: (scope) {
      scope.setTag('auth_outcome', authOutcome);
      if (authMethod != null) {
        scope.setTag('auth_method', authMethod);
      }
      if (isValidAuthAttemptId(authAttemptId)) {
        scope.setTag('auth_attempt_id', authAttemptId!);
      }
    },
  );
}

String? sanitizeAuthAttemptIdQuery(String? raw) {
  if (!isValidAuthAttemptId(raw)) return null;
  return raw;
}

/// Split Google OAuth `state` query value into CSRF state + optional attempt id.
(String csrfState, String? attemptId) parseOAuthStateQuery(String raw) {
  if (raw.isEmpty) return ('', null);
  final dot = raw.indexOf('.');
  if (dot <= 0) return (raw, null);
  final csrf = raw.substring(0, dot);
  final attempt = sanitizeAuthAttemptIdQuery(raw.substring(dot + 1));
  return (csrf, attempt);
}
