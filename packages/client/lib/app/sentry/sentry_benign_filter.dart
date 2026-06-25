import 'package:logging/logging.dart';

import 'package:tentura/data/service/remote_api_client/exception.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/auth/domain/exception.dart';

/// Whether [error] is an expected, user-facing failure that should not
/// become a Sentry issue (connectivity loss, session expiry, etc.).
bool isBenignSentryThrowable(Object? error) {
  if (error == null) {
    return false;
  }
  if (error is ConnectionUplinkException ||
      error is AuthSessionLostException ||
      error is AuthenticationNoKeyException) {
    return true;
  }
  if (error.toString().toLowerCase().contains('socketexception')) {
    return true;
  }
  return false;
}

bool _isBenignSentryMessage(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('socketexception')) {
    return true;
  }
  // Logged when auth is cleared while in-flight GraphQL requests still run.
  if (lower.contains('key pair is not set')) {
    return true;
  }
  return false;
}

bool isBenignSentryLogRecord(LogRecord record) {
  if (isBenignSentryThrowable(record.error)) {
    return true;
  }
  if (_isBenignSentryMessage(record.message)) {
    return true;
  }
  return false;
}
