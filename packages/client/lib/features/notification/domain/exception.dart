sealed class FcmException implements Exception {
  const FcmException([this.message]);

  final Object? message;
}

/// Server rejected/failed to persist the token (e.g. DB write failed).
/// Must not be swallowed as success — caching the local registration record
/// on this would strand the device as "registered" forever with no
/// server-side row.
final class FcmRegistrationRejectedException extends FcmException {
  const FcmRegistrationRejectedException([super.message]);
}

/// Notification permission is not granted, so there is no token to register.
final class FcmPermissionDeniedException extends FcmException {
  const FcmPermissionDeniedException([super.message]);
}

/// No signed-in account to register a device for.
final class FcmNoActiveAccountException extends FcmException {
  const FcmNoActiveAccountException([super.message]);
}
