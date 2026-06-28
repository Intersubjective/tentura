import 'package:logging/logging.dart';

import 'package:tentura/data/service/remote_api_client/exception.dart';
import 'package:tentura/domain/exception/generic_exception.dart';
import 'package:tentura/domain/exception/user_input_exception.dart';
import 'package:tentura/features/auth/domain/exception.dart';

/// Whether [error] is an expected, user-facing failure that should not
/// become a Sentry issue (connectivity loss, session expiry, etc.).
bool isBenignSentryThrowable(Object? error) {
  if (error == null) {
    return false;
  }
  if (error is ConnectionUplinkException ||
      error is AuthSessionLostException ||
      error is AuthenticationNoKeyException ||
      error is SessionAuthRejectedException) {
    return true;
  }
  if (error is UserInputException || error is PollingInputExceptions) {
    return true;
  }
  if (error is AuthSeedIsWrongException ||
      error is InvitationCodeIsWrongException ||
      error is AuthIdIsWrongException ||
      error is AuthIdNotFoundException ||
      error is AuthSeedExistsException) {
    return true;
  }
  return isBenignSentryExceptionText(error.toString());
}

bool isBenignSentryExceptionText(String text) {
  final lower = text.toLowerCase();
  if (lower.contains('socketexception')) {
    return true;
  }
  // Logged when auth is cleared while in-flight GraphQL requests still run.
  if (lower.contains('key pair is not set')) {
    return true;
  }
  // FCM push SW: CDN/importScripts timeouts, privacy browsers, offline, etc.
  if (lower.contains('failed to register a serviceworker') ||
      lower.contains('timed out while trying to start the service worker')) {
    return true;
  }
  return false;
}

bool _isBenignSentryMessage(String message) =>
    isBenignSentryExceptionText(message);

bool isBenignSentryLogRecord(LogRecord record) {
  if (isBenignSentryThrowable(record.error)) {
    return true;
  }
  if (_isBenignSentryMessage(record.message)) {
    return true;
  }
  return false;
}
