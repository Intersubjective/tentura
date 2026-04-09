import 'package:tentura_root/domain/entity/localizable.dart';

final class MovedToMyWorkMessage extends LocalizableMessage {
  const MovedToMyWorkMessage();

  @override
  String get toEn =>
      'Removed from Inbox and moved to My Work';

  @override
  String get toRu =>
      'Убрано из Входящих и перенесено в Мои дела';
}

final class MovedToInboxMessage extends LocalizableMessage {
  const MovedToInboxMessage();

  @override
  String get toEn =>
      'Commitment withdrawn — the beacon is in Watching (not in Needs me).';

  @override
  String get toRu =>
      'Обязательство отозвано — маяк в «Наблюдении», не в «Нужно мне».';
}
