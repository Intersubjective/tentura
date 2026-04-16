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

  const UserExceptionCodes(this.exceptionCode);

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

// Evaluation (beacon-local review)

enum EvaluationExceptionCode {
  unspecified,
  reviewWindowNotOpen,
  notEligible,
  evaluationAlreadySubmitted,
  reasonTagRequired,
  reviewWindowExpired,
  beaconNotClosable,
  invalidEvaluationValue,
  invalidReasonTags,
}

class EvaluationExceptionCodes extends ExceptionCodes {
  static const codeSpace = 1400;

  const EvaluationExceptionCodes(this.exceptionCode);

  final EvaluationExceptionCode exceptionCode;

  @override
  int get codeNumber => codeSpace + exceptionCode.index;
}

// Commitment / overcommit coordination

enum CommitmentCoordinationExceptionCode {
  beaconNotOpen,
  notBeaconAuthor,
  invalidHelpType,
  invalidUncommitReason,
  invalidResponseType,
  invalidCoordinationStatus,
  commitmentNotActive,
  authorCannotCommit,
  beaconWithdrawForbidden,
}

class CommitmentCoordinationExceptionCodes extends ExceptionCodes {
  static const codeSpace = 1500;

  const CommitmentCoordinationExceptionCodes(this.exceptionCode);

  final CommitmentCoordinationExceptionCode exceptionCode;

  @override
  int get codeNumber => codeSpace + exceptionCode.index;
}
