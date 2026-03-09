import 'dart:convert';

import 'exception_codes.dart';

part 'exception/fcm_exceprions.dart';

base class ExceptionBase implements Exception {
  const ExceptionBase({
    required this.code,
    required this.description,
    this.path = '',
  });

  final ExceptionCodes code;
  final String description;
  final String path;

  Map<String, Object> get toMap => {
    'message': description,
    'extensions': {'code': '${code.codeNumber}', 'path': path},
  };

  @override
  String toString() => jsonEncode(toMap);
}

final class UnspecifiedException extends ExceptionBase {
  const UnspecifiedException({
    String? description,
    String? path,
  }) : super(
         code: const GeneralExceptionCodes(
           GeneralExceptionCode.unspecifiedException,
         ),
         description: description ?? 'Unspecified exception',
         path: path ?? '',
       );
}

final class IdNotFoundException extends ExceptionBase {
  const IdNotFoundException({
    String id = '',
    String? description,
  }) : super(
         code: const GeneralExceptionCodes(
           GeneralExceptionCode.idNotFoundException,
         ),
         description: description ?? 'Id not found: [$id]',
       );
}

final class IdWrongException extends ExceptionBase {
  const IdWrongException({
    String id = '',
    String? description,
  }) : super(
         code: const GeneralExceptionCodes(
           GeneralExceptionCode.idNotFoundException,
         ),
         description: description ?? 'Wrong Id: [$id]',
       );
}

final class IdDuplicateException extends ExceptionBase {
  const IdDuplicateException({
    String id = '',
    String? description,
  }) : super(
         code: const GeneralExceptionCodes(
           GeneralExceptionCode.idDuplicateException,
         ),
         description: description ?? 'Id already exists: [$id]',
       );
}

final class PemKeyWrongException extends ExceptionBase {
  const PemKeyWrongException({
    String key = '',
    String? description,
  }) : super(
         code: const GeneralExceptionCodes(
           GeneralExceptionCode.idNotFoundException,
         ),
         description: description ?? 'Wrong PEM keys: [$key]',
       );

  @override
  String toString() => 'Wrong PEM keys: [$description]';
}

final class AuthorizationHeaderWrongException extends ExceptionBase {
  const AuthorizationHeaderWrongException({String? description})
    : super(
        code: const AuthExceptionCodes(
          AuthExceptionCode.authAuthorizationHeaderWrongException,
        ),
        description: description ?? 'Wrong Authorization header',
      );
}

final class UnauthorizedException extends ExceptionBase {
  const UnauthorizedException({String? description})
    : super(
        code: const AuthExceptionCodes(
          AuthExceptionCode.authAuthorizationHeaderWrongException,
        ),
        description: description ?? 'User is not authorized',
      );
}

final class InvitationWrongException extends ExceptionBase {
  const InvitationWrongException({String? description})
    : super(
        code: const AuthExceptionCodes(
          AuthExceptionCode.authInvitationWrongException,
        ),
        description: description ?? 'Wrong invitation code',
      );
}

final class BeaconCreateException extends ExceptionBase {
  const BeaconCreateException({String? description})
    : super(
        code: const BeaconExceptionCodes(
          BeaconExceptionCode.beaconCreateException,
        ),
        description: description ?? 'Beacon create error',
      );
}
