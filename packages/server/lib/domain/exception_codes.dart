sealed class ExceptionCodes {
  const ExceptionCodes();

  int get codeNumber;
}

enum GeneralExceptionCode {
  unspecifiedException,
  idWrongException,
  idNotFoundException,
  idDuplicateException,
}

class GeneralExceptionCodes extends ExceptionCodes {
  static const codeSpace = 1000;

  const GeneralExceptionCodes(this.exceptionCode);

  final GeneralExceptionCode exceptionCode;

  @override
  int get codeNumber => codeSpace + exceptionCode.index;
}

// Auth

enum AuthExceptionCode {
  unspecifiedException,
  authPemKeyWrongException,
  authUnauthorizedException,
  authInvitationWrongException,
  authAuthorizationHeaderWrongException,
}

class AuthExceptionCodes extends ExceptionCodes {
  static const codeSpace = 1100;

  const AuthExceptionCodes(this.exceptionCode);

  final AuthExceptionCode exceptionCode;

  @override
  int get codeNumber => codeSpace + exceptionCode.index;
}

// User
enum UserExceptionCode {
  unspecifiedException,
}

class UserExceptionCodes extends ExceptionCodes {
  static const codeSpace = 1200;

  UserExceptionCodes(this.exceptionCode);

  final UserExceptionCode exceptionCode;

  @override
  int get codeNumber => codeSpace + exceptionCode.index;
}

// Beacon

enum BeaconExceptionCode {
  unspecifiedException,
  beaconCreateException,
}

class BeaconExceptionCodes extends ExceptionCodes {
  static const codeSpace = 1300;

  const BeaconExceptionCodes(this.exceptionCode);

  final BeaconExceptionCode exceptionCode;

  @override
  int get codeNumber => codeSpace + exceptionCode.index;
}
