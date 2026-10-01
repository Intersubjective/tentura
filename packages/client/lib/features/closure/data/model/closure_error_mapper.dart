import '../../domain/closure_exception.dart';

/// Throws the matching [ClosureException] for a recognized closure GraphQL
/// error [code]. Returns normally for any other code so the caller can fall
/// through to generic mapping.
void throwIfClosureError(int? code) {
  switch (code) {
    case ClosureNotAuthorException.codeNumber:
      throw const ClosureNotAuthorException();
    case ClosureNotVoterException.codeNumber:
      throw const ClosureNotVoterException();
    case ClosureNotMemberException.codeNumber:
      throw const ClosureNotMemberException();
    case ClosureStaleEpochException.codeNumber:
      throw const ClosureStaleEpochException();
    case ClosureWrongStatusException.codeNumber:
      throw const ClosureWrongStatusException();
    case ClosureReopenLimitException.codeNumber:
      throw const ClosureReopenLimitException();
    case ClosureExtendLimitException.codeNumber:
      throw const ClosureExtendLimitException();
    case ClosureNotReadyException.codeNumber:
      throw const ClosureNotReadyException();
    case ClosureInvalidSplitException.codeNumber:
      throw const ClosureInvalidSplitException();
    case ClosureSplitTooLargeException.codeNumber:
      throw const ClosureSplitTooLargeException();
  }
}
