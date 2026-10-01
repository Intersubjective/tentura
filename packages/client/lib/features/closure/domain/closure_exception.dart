import 'package:tentura_root/domain/entity/localizable.dart';

/// Typed translations of the closure GraphQL error codes (`ClosureException`
/// on the server, code space 1800 + enum index).
///
/// Thrown by `onGraphQLError` in
/// `data/service/remote_api_client/build_client.dart`.
sealed class ClosureException extends LocalizableException {
  const ClosureException();
}

final class ClosureNotAuthorException extends ClosureException {
  const ClosureNotAuthorException();

  static const codeNumber = 1800;

  @override
  String get toEn => 'Only the author of this request can do that.';

  @override
  String get toRu => 'Это может сделать только автор запроса.';
}

final class ClosureNotVoterException extends ClosureException {
  const ClosureNotVoterException();

  static const codeNumber = 1801;

  @override
  String get toEn => 'You are not among the people who sum up this request.';

  @override
  String get toRu => 'Вы не входите в число тех, кто подводит итоги запроса.';
}

final class ClosureNotMemberException extends ClosureException {
  const ClosureNotMemberException();

  static const codeNumber = 1802;

  @override
  String get toEn => 'You did not help with this request.';

  @override
  String get toRu => 'Вы не участвовали в помощи по этому запросу.';
}

final class ClosureStaleEpochException extends ClosureException {
  const ClosureStaleEpochException();

  static const codeNumber = 1803;

  @override
  String get toEn => 'This request has changed. Reload and try again.';

  @override
  String get toRu => 'Запрос изменился. Обновите страницу и повторите.';
}

final class ClosureWrongStatusException extends ClosureException {
  const ClosureWrongStatusException();

  static const codeNumber = 1804;

  @override
  String get toEn => 'This is not possible at the current stage of the request.';

  @override
  String get toRu => 'Это невозможно на текущем этапе запроса.';
}

final class ClosureReopenLimitException extends ClosureException {
  const ClosureReopenLimitException();

  static const codeNumber = 1805;

  @override
  String get toEn => 'This request cannot be reopened any more.';

  @override
  String get toRu => 'Этот запрос больше нельзя открыть заново.';
}

final class ClosureExtendLimitException extends ClosureException {
  const ClosureExtendLimitException();

  static const codeNumber = 1806;

  @override
  String get toEn => 'The summing-up time cannot be extended any more.';

  @override
  String get toRu => 'Время подведения итогов больше нельзя продлить.';
}

final class ClosureNotReadyException extends ClosureException {
  const ClosureNotReadyException();

  static const codeNumber = 1807;

  @override
  String get toEn => 'Not everyone has answered yet.';

  @override
  String get toRu => 'Ещё не все ответили.';
}

final class ClosureInvalidSplitException extends ClosureException {
  const ClosureInvalidSplitException();

  static const codeNumber = 1808;

  @override
  String get toEn => 'The split is not valid. The shares must add up to 100%.';

  @override
  String get toRu => 'Распределение неверно. Доли должны давать в сумме 100%.';
}

final class ClosureSplitTooLargeException extends ClosureException {
  const ClosureSplitTooLargeException();

  static const codeNumber = 1809;

  @override
  String get toEn => 'The split lists too many people.';

  @override
  String get toRu => 'В распределении слишком много людей.';
}
