import 'package:tentura_root/domain/entity/localizable.dart';

/// Typed translations of the review GraphQL error codes (`EvaluationException`
/// on the server, code space 1400).
///
/// Thrown by `onGraphQLError` in
/// `data/service/remote_api_client/build_client.dart`, the same way the
/// nested-request and constellation codes are mapped there. Without this the
/// server's default description — the bare enum name, e.g. `notEligible` —
/// reached the snackbar verbatim (issue #161).
sealed class EvaluationException extends LocalizableException {
  const EvaluationException();
}

/// The review window for this request is not open (yet).
final class EvaluationReviewWindowNotOpenException extends EvaluationException {
  const EvaluationReviewWindowNotOpenException();

  static const codeNumber = 1401;

  @override
  String get toEn => 'Reviews are not open for this request.';

  @override
  String get toRu => 'Отзывы по этому запросу сейчас недоступны.';
}

/// The viewer may not review this participant (role/participation mismatch).
final class EvaluationNotEligibleException extends EvaluationException {
  const EvaluationNotEligibleException();

  static const codeNumber = 1402;

  @override
  String get toEn => 'You cannot review this person in this request.';

  @override
  String get toRu => 'Вы не можете оценить этого человека в этом запросе.';
}

/// The review was already submitted and cannot be replaced.
final class EvaluationAlreadySubmittedException extends EvaluationException {
  const EvaluationAlreadySubmittedException();

  static const codeNumber = 1403;

  @override
  String get toEn => 'This review has already been submitted.';

  @override
  String get toRu => 'Этот отзыв уже отправлен.';
}

/// The review window closed before this review was sent.
final class EvaluationReviewWindowExpiredException extends EvaluationException {
  const EvaluationReviewWindowExpiredException();

  static const codeNumber = 1405;

  @override
  String get toEn => 'The review window has closed.';

  @override
  String get toRu => 'Окно отзывов уже закрыто.';
}
