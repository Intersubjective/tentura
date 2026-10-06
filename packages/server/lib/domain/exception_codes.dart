sealed class ExceptionCodes {
  const ExceptionCodes();

  int get codeNumber;
}

enum GeneralExceptionCode {
  unspecifiedException,
  idWrongException,
  idNotFoundException,
  idDuplicateException,
  payloadTooLargeException,
  rateLimitedException,
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
  authCredentialConflictException,
  authLastCredentialException,
  oidcStateMismatch,
  oidcTokenExchangeFailed,
  oidcIdTokenInvalid,
  oidcProviderDisabled,
  oidcInviteRequired,
  authAmbiguousIdentity,
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
  beaconNeedSummaryTooShort,
  beaconFactCardAlreadyPinned,
  beaconPrimaryNeedInvalid, // 1304
  beaconPrimaryNeedNotInNeeds, // 1305
  beaconImageNotAttached, // 1306
  beaconCoverNotAttached, // 1307
  beaconMediaInvalid, // 1308
  beaconChildCreateForbidden, // 1309
  beaconParentNotCoordinatable, // 1310
  beaconPromotionSourceInvalid, // 1311
  beaconSourceAlreadyPromoted, // 1312
  beaconChildCommandConflict, // 1313
  beaconChildCommandGone, // 1314
  discussionScopeDisabled, // 1315
  coordinationKindDisabled, // 1316
  beaconHierarchyCursorInvalid, // 1317
  beaconFactCardEditConflict, // 1318
  beaconFactCardRemoved, // 1319
  beaconFactCardRateLimited, // 1320
  beaconNotRequest, // 1321
  batonNotFound, // 1322
  batonNotAuthor, // 1323
  batonNotCandidate, // 1324
  batonNotCollecting, // 1325
  batonInvalidCandidates, // 1326
  batonAlreadyActive, // 1327
  batonTakerNotAvailable, // 1328
  batonMessageNotEligible, // 1329
  planEditConflict, // 1330
  planStepNotFound, // 1331
  planNotEditable, // 1332
  planActionStale, // 1333
  planRestoreSourceMissing, // 1334
  planRateLimited, // 1335
  planAssigneeNotAdmitted, // 1336
  planTooLarge, // 1337
  planDisabled, // 1338
  planInvalid, // 1339
}

class BeaconExceptionCodes extends ExceptionCodes {
  static const codeSpace = 1300;

  const BeaconExceptionCodes(this.exceptionCode);

  final BeaconExceptionCode exceptionCode;

  @override
  int get codeNumber => codeSpace + exceptionCode.index;
}

// Beacon lifecycle (cancel / delete / status) exceptions

/// Indices are wire codes (1400 + index); retired values keep their slot.
enum EvaluationExceptionCode {
  unspecified,
  retired1401,
  notEligible,
  retired1403,
  retired1404,
  retired1405,
  beaconNotClosable,
  retired1407,
  retired1408,
  retired1409,
  retired1410,
  retired1411,
  retired1412,
  retired1413,
}

class EvaluationExceptionCodes extends ExceptionCodes {
  static const codeSpace = 1400;

  const EvaluationExceptionCodes(this.exceptionCode);

  final EvaluationExceptionCode exceptionCode;

  @override
  int get codeNumber => codeSpace + exceptionCode.index;
}

// HelpOffer / coordination

enum HelpOfferCoordinationExceptionCode {
  beaconNotOpen,
  notBeaconAuthor,
  invalidHelpType,
  invalidWithdrawReason,
  invalidResponseType,
  invalidCoordinationStatus,
  helpOfferNotActive,
  authorCannotCommit,
  beaconWithdrawForbidden,
  reasonRequired,
  reasonTooLong,
  notAdmitted,
  alreadyAdmitted,
  commitmentAlreadyAcknowledged,
  admissionRequiresAcknowledgement,
  commitmentNotAcknowledged,
  offerKindChanged,
  invalidRoleLabel,
}

class HelpOfferCoordinationExceptionCodes extends ExceptionCodes {
  static const codeSpace = 1500;

  const HelpOfferCoordinationExceptionCodes(this.exceptionCode);

  final HelpOfferCoordinationExceptionCode exceptionCode;

  @override
  int get codeNumber => codeSpace + exceptionCode.index;
}

// Capability

enum CapabilityExceptionCode {
  invalidSlug,
  selfLabelForbidden,
}

class CapabilityExceptionCodes extends ExceptionCodes {
  static const codeSpace = 1600;

  const CapabilityExceptionCodes(this.exceptionCode);

  final CapabilityExceptionCode exceptionCode;

  @override
  int get codeNumber => codeSpace + exceptionCode.index;
}

// Constellation pinning (C4)

enum ConstellationExceptionCode {
  invalidTarget,
  invalidCoordinates,
  unsupportedCoordinateSpace,
  targetUnavailable,
}

class ConstellationExceptionCodes extends ExceptionCodes {
  static const codeSpace = 1700;

  const ConstellationExceptionCodes(this.exceptionCode);

  final ConstellationExceptionCode exceptionCode;

  @override
  int get codeNumber => codeSpace + exceptionCode.index;
}

// Episode closure (A12)

enum ClosureExceptionCode {
  notAuthor,
  notVoter,
  notMember,
  staleEpoch,
  wrongStatus,
  reopenLimit,
  extendLimit,
  notReady,
  invalidSplit,
  splitTooLarge,
}

class ClosureExceptionCodes extends ExceptionCodes {
  static const codeSpace = 1800;

  const ClosureExceptionCodes(this.exceptionCode);

  final ClosureExceptionCode exceptionCode;

  @override
  int get codeNumber => codeSpace + exceptionCode.index;
}
