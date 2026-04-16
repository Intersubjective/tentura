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
