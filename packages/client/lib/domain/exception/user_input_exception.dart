import 'package:tentura_root/domain/entity/localizable.dart';

abstract class UserInputException extends LocalizableException {
  const UserInputException();
}

final class TitleTooShortException extends UserInputException {
  const TitleTooShortException();

  @override
  String get toEn => 'Title is too short';

  @override
  String get toRu => 'Название слишком короткое';
}

final class BeaconNeedSummaryTooShortException extends UserInputException {
  const BeaconNeedSummaryTooShortException();

  @override
  String get toEn => 'Describe the need in at least 16 characters.';

  @override
  String get toRu => 'Опишите потребность не короче 16 символов.';
}

/// Polling Input Exceptions
sealed class PollingInputExceptions extends LocalizableException {
  const PollingInputExceptions();
}

final class PollingQuestionTooShortException extends PollingInputExceptions {
  const PollingQuestionTooShortException();

  @override
  String get toEn => 'Too short question';

  @override
  String get toRu => 'Слишком короткий вопрос';
}

final class PollingVariantTooShortException extends PollingInputExceptions {
  const PollingVariantTooShortException();

  @override
  String get toEn => 'Too short variant';

  @override
  String get toRu => 'Слишком короткий вариант ответа';
}

final class PollingTooFewVariantsException extends PollingInputExceptions {
  const PollingTooFewVariantsException();

  @override
  String get toEn => 'Too few variants';

  @override
  String get toRu => 'Слишком мало вариантов ответа';
}

final class PollingVariantsNotUniqueException extends PollingInputExceptions {
  const PollingVariantsNotUniqueException();

  @override
  String get toEn => 'Variants must be unique';

  @override
  String get toRu => 'Варианты ответов не должны повторяться';
}
