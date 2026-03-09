import 'package:tentura/ui/message/action_message_base.dart';

final class BeaconCreatedMessage extends LocalizableActionMessage {
  const BeaconCreatedMessage({
    required this.onPressed,
  });

  @override
  String get toEn => 'Beacon created successfully!';

  @override
  String get toRu => 'Маяк успешно создан!';

  @override
  final void Function() onPressed;

  @override
  LocalizableMessage get label => const _BeaconCreatedMessageActionLabel();
}

final class _BeaconCreatedMessageActionLabel extends LocalizableMessage {
  const _BeaconCreatedMessageActionLabel();

  @override
  String get toEn => 'View Beacon';

  @override
  String get toRu => 'Посмотреть';
}
