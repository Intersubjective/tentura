/// Typed translations of the «Who'll take it?» (baton) GraphQL error codes
/// 1322–1329 (plan `docs/plans/baton-who-takes-it-plan.md`).
///
/// Thrown by the routing link's `onGraphQLError` handler in
/// `data/service/remote_api_client/build_client.dart` when it recognizes one
/// of these codes in a GraphQL error's `extensions.code`.
sealed class BatonException implements Exception {
  const BatonException([this.message]);

  final Object? message;

  @override
  String toString() => message?.toString() ?? super.toString();
}

/// The baton does not exist.
final class BatonNotFoundException extends BatonException {
  const BatonNotFoundException([super.message]);

  static const codeNumber = 1322;
}

/// Only the author of the message may do this.
final class BatonNotAuthorException extends BatonException {
  const BatonNotAuthorException([super.message]);

  static const codeNumber = 1323;
}

/// The caller is not one of the baton's candidates.
final class BatonNotCandidateException extends BatonException {
  const BatonNotCandidateException([super.message]);

  static const codeNumber = 1324;
}

/// The baton is no longer collecting answers.
final class BatonNotCollectingException extends BatonException {
  const BatonNotCollectingException([super.message]);

  static const codeNumber = 1325;
}

/// The candidate list is empty, too long, duplicated or has invalid tiers.
final class BatonInvalidCandidatesException extends BatonException {
  const BatonInvalidCandidatesException([super.message]);

  static const codeNumber = 1326;
}

/// The message already has a live baton.
final class BatonAlreadyActiveException extends BatonException {
  const BatonAlreadyActiveException([super.message]);

  static const codeNumber = 1327;
}

/// Nobody eligible (or the chosen person is not eligible) to take it.
final class BatonTakerNotAvailableException extends BatonException {
  const BatonTakerNotAvailableException([super.message]);

  static const codeNumber = 1328;
}

/// The message cannot carry a baton.
final class BatonMessageNotEligibleException extends BatonException {
  const BatonMessageNotEligibleException([super.message]);

  static const codeNumber = 1329;
}

/// Throws the matching [BatonException] for a recognized baton GraphQL error
/// [code]. Returns normally (no throw) for any other code, so the caller
/// falls through to its generic mapping.
void throwIfBatonError(int? code) {
  switch (code) {
    case BatonNotFoundException.codeNumber:
      throw const BatonNotFoundException();
    case BatonNotAuthorException.codeNumber:
      throw const BatonNotAuthorException();
    case BatonNotCandidateException.codeNumber:
      throw const BatonNotCandidateException();
    case BatonNotCollectingException.codeNumber:
      throw const BatonNotCollectingException();
    case BatonInvalidCandidatesException.codeNumber:
      throw const BatonInvalidCandidatesException();
    case BatonAlreadyActiveException.codeNumber:
      throw const BatonAlreadyActiveException();
    case BatonTakerNotAvailableException.codeNumber:
      throw const BatonTakerNotAvailableException();
    case BatonMessageNotEligibleException.codeNumber:
      throw const BatonMessageNotEligibleException();
  }
}
