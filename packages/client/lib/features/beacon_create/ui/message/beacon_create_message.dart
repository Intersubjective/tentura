import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';
import 'package:tentura/ui/message/action_message_base.dart';

final class BeaconCreatedMessage extends LocalizableActionMessage {
  const BeaconCreatedMessage({
    required this.onPressed,
  });

  @override
  String get toEn => 'Request created successfully!';

  @override
  String get toRu => 'Запрос успешно создан!';

  @override
  final void Function() onPressed;

  @override
  LocalizableMessage get label => const _BeaconCreatedMessageActionLabel();
}

final class _BeaconCreatedMessageActionLabel extends LocalizableMessage {
  const _BeaconCreatedMessageActionLabel();

  @override
  String get toEn => 'View Request';

  @override
  String get toRu => 'Посмотреть запрос';
}

final class DraftSavedMessage extends LocalizableMessage {
  const DraftSavedMessage();

  @override
  String get toEn => 'Draft saved';

  @override
  String get toRu => 'Черновик сохранён';
}

/// Edit request › Save changes went through (#510).
final class BeaconChangesSavedMessage extends LocalizableMessage {
  const BeaconChangesSavedMessage();

  @override
  String get toEn => 'Changes saved';

  @override
  String get toRu => 'Изменения сохранены';
}

/// Save changes wrote the fields, but the photos and cover could not be
/// sent; the editor stays open so Save changes can send them again (#510).
final class BeaconPhotosNotUpdatedMessage extends LocalizableMessage {
  const BeaconPhotosNotUpdatedMessage();

  // The button is named by its own l10n label, so the words always match it.
  @override
  String get toEn =>
      'Changes saved, but the photos were not updated. '
      'Tap “${L10nEn().buttonSaveChanges}” again.';

  @override
  String get toRu =>
      'Изменения сохранены, но фото не обновились. '
      'Нажмите «${L10nRu().buttonSaveChanges}» ещё раз.';
}

final class RequestMadeLiveMessage extends LocalizableMessage {
  const RequestMadeLiveMessage();

  @override
  String get toEn => 'Request is live';

  @override
  String get toRu => 'Запрос запущен';
}

/// The request was closed, cancelled or deleted, so it cannot be edited.
final class BeaconNotEditableMessage extends LocalizableMessage {
  const BeaconNotEditableMessage();

  @override
  String get toEn => 'This request can no longer be edited';

  @override
  String get toRu => 'Этот запрос больше нельзя редактировать';
}
