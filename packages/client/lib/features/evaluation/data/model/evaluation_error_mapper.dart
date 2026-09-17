import '../../domain/evaluation_exception.dart';

/// Throws the matching [EvaluationException] for a recognized review GraphQL
/// error [code]. Returns normally for any other code so the caller can fall
/// through to generic mapping.
void throwIfEvaluationError(int? code) {
  switch (code) {
    case EvaluationReviewWindowNotOpenException.codeNumber:
      throw const EvaluationReviewWindowNotOpenException();
    case EvaluationNotEligibleException.codeNumber:
      throw const EvaluationNotEligibleException();
    case EvaluationAlreadySubmittedException.codeNumber:
      throw const EvaluationAlreadySubmittedException();
    case EvaluationReviewWindowExpiredException.codeNumber:
      throw const EvaluationReviewWindowExpiredException();
  }
}
