import 'dart:convert';

import 'enum.dart';
import 'exception_codes.dart';

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

final class IdNotFoundException extends ExceptionBase {
  const IdNotFoundException({String id = '', String? description})
    : super(
        code: const AuthExceptionCodes(
          AuthExceptionCode.authIdNotFoundException,
        ),
        description: description ?? 'Id not found: [$id]',
      );
}

final class IdWrongException extends ExceptionBase {
  const IdWrongException({String id = '', String? description})
    : super(
        code: const AuthExceptionCodes(
          AuthExceptionCode.authIdNotFoundException,
        ),
        description: description ?? 'Wrong Id: [$id]',
      );
}

final class PemKeyWrongException extends ExceptionBase {
  const PemKeyWrongException({String key = '', String? description})
    : super(
        code: const AuthExceptionCodes(
          AuthExceptionCode.authIdNotFoundException,
        ),
        description: description ?? 'Wrong PEM keys: [$key]',
      );

  @override
  String toString() => 'Wrong PEM keys: [$description]';
}

final class AuthorizationHeaderWrongException extends ExceptionBase {
  const AuthorizationHeaderWrongException()
    : super(
        code: const AuthExceptionCodes(
          AuthExceptionCode.authAuthorizationHeaderWrongException,
        ),
        description: 'Wrong Authorization header',
      );
}

final class UnauthorizedException extends ExceptionBase {
  const UnauthorizedException()
    : super(
        code: const AuthExceptionCodes(
          AuthExceptionCode.authAuthorizationHeaderWrongException,
        ),
        description: 'Wrong Authorization header',
      );
}
