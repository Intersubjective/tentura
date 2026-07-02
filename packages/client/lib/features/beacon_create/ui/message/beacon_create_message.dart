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
