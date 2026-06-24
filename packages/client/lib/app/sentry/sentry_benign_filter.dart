import 'package:logging/logging.dart';

import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/features/auth/domain/exception.dart';

/// Whether [error] is an expected, user-facing failure that should not
/// become a Sentry issue (connectivity loss, session expiry, etc.).
bool isBenignSentryThrowable(Object? error) {
  if (error == null) {
    return false;
  }
  if (error is ConnectionUplinkException || error is AuthSessionLostException) {
    return true;
  }
  if (error.toString().toLowerCase().contains('socketexception')) {
    return true;
  }
  return false;
}

bool isBenignSentryLogRecord(LogRecord record) {
  if (isBenignSentryThrowable(record.error)) {
    return true;
  }
  if (record.message.toLowerCase().contains('socketexception')) {
    return true;
  }
  return false;
}
