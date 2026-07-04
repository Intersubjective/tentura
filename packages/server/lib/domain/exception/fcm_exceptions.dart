part of '../exception.dart';

final class FcmTokenNotFoundException extends ExceptionBase {
  const FcmTokenNotFoundException({
    required this.token,
    String? description,
  }) : super(
         code: const GeneralExceptionCodes(
           GeneralExceptionCode.idNotFoundException,
         ),
         description: description ?? 'Token not found: [$token]',
       );

  final String token;
}

final class FcmUnauthorizedException extends ExceptionBase {
  const FcmUnauthorizedException({
    String? description,
  }) : super(
         code: const GeneralExceptionCodes(
           GeneralExceptionCode.unspecifiedException,
         ),
         description: description ?? 'Fcm unauthorized',
       );
}

/// FCM rejected this specific token's delivery for a documented per-message
/// reason (e.g. THIRD_PARTY_AUTH_ERROR when a browser's push relay — Mozilla
/// autopush, not Google's own infra — can't validate our VAPID auth).
/// Scoped to one recipient: unlike [FcmUnauthorizedException] (our own
/// access token is bad), this must not abort the rest of the send batch.
final class FcmMessageRejectedException extends ExceptionBase {
  const FcmMessageRejectedException({
    required this.token,
    required this.errorCode,
    String? description,
  }) : super(
         code: const GeneralExceptionCodes(
           GeneralExceptionCode.unspecifiedException,
         ),
         description: description ?? 'FCM rejected token [$token]: $errorCode',
       );

  final String token;
  final String errorCode;
}
