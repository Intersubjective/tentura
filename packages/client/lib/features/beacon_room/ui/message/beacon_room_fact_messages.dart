import 'package:tentura/ui/message/action_message_base.dart';

/// Snack shown when pinning is blocked — action opens the facts sheet (via cubit hook).
final class BeaconFactAlreadyPinnedSnackMessage extends LocalizableActionMessage {
  BeaconFactAlreadyPinnedSnackMessage({required void Function() onOpenFacts}) : _onOpenFacts = onOpenFacts;

  final void Function() _onOpenFacts;

  @override
  String get toEn => 'This message already has a pinned fact.';

  @override
  String get toRu => 'У этого сообщения уже есть закреплённый факт.';

  @override
  void Function() get onPressed => _onOpenFacts;

  @override
  LocalizableMessage get label => const _BeaconFactAlreadyPinnedSnackActionLabel();
}

final class _BeaconFactAlreadyPinnedSnackActionLabel extends LocalizableMessage {
  const _BeaconFactAlreadyPinnedSnackActionLabel();

  @override
  String get toEn => 'View facts';

  @override
  String get toRu => 'Открыть';
}

final class BeaconFactPinSuccessMessage extends LocalizableMessage {
  const BeaconFactPinSuccessMessage();

  @override
  String get toEn => 'Fact pinned.';

  @override
  String get toRu => 'Факт закреплён.';
}

final class BeaconFactRemoveSuccessMessage extends LocalizableMessage {
  const BeaconFactRemoveSuccessMessage();

  @override
  String get toEn => 'Fact unpinned.';

  @override
  String get toRu => 'Факт откреплён.';
}

final class BeaconFactEditSuccessMessage extends LocalizableMessage {
  const BeaconFactEditSuccessMessage();

  @override
  String get toEn => 'Fact updated.';

  @override
  String get toRu => 'Факт обновлён.';
}

final class BeaconFactVisibilitySuccessMessage extends LocalizableMessage {
  const BeaconFactVisibilitySuccessMessage();

  @override
  String get toEn => 'Fact visibility updated.';

  @override
  String get toRu => 'Видимость факта обновлена.';
}

final class BeaconFactCopiedMessage extends LocalizableMessage {
  const BeaconFactCopiedMessage();

  @override
  String get toEn => 'Copied to clipboard.';

  @override
  String get toRu => 'Скопировано в буфер обмена.';
}
