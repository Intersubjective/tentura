import 'package:tentura/ui/message/action_message_base.dart';

/// Snack shown when pinning is blocked — action opens the facts sheet (via cubit hook).
final class BeaconFactAlreadyPinnedSnackMessage
    extends LocalizableActionMessage {
  BeaconFactAlreadyPinnedSnackMessage({required this._onOpenFacts});

  final void Function() _onOpenFacts;

  @override
  String get toEn => 'This message already has a pinned fact.';

  @override
  String get toRu => 'У этого сообщения уже есть закреплённый факт.';

  @override
  void Function() get onPressed => _onOpenFacts;

  @override
  LocalizableMessage get label =>
      const _BeaconFactAlreadyPinnedSnackActionLabel();
}

final class _BeaconFactAlreadyPinnedSnackActionLabel
    extends LocalizableMessage {
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

final class BeaconFactPinMessageKeptMessage extends LocalizableMessage {
  const BeaconFactPinMessageKeptMessage();

  @override
  String get toEn =>
      'Posted to the discussion, but the fact could not be pinned.';

  @override
  String get toRu =>
      'Сообщение в обсуждении отправлено, но закрепить факт не удалось.';
}

/// Add-fact (#759, review r1 #4): the posted message already carries a
/// different fact, pinned by someone else; ours was not saved.
final class BeaconFactPinTakenMessage extends LocalizableMessage {
  const BeaconFactPinTakenMessage();

  @override
  String get toEn =>
      'Posted to the discussion, but that message already has a different '
      'pinned fact. Your fact was not pinned.';

  @override
  String get toRu =>
      'Сообщение в обсуждении отправлено, но к нему уже закреплён другой '
      'факт. Ваш факт не закреплён.';
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

/// Shown when a reply quote jump cannot load the original message (P6 wires l10n).
final class RoomReplyTargetUnavailableMessage extends LocalizableMessage {
  const RoomReplyTargetUnavailableMessage();

  @override
  String get toEn => 'Original message could not be loaded';

  @override
  String get toRu => 'Не удалось загрузить исходное сообщение';
}

final class BeaconFactCopiedMessage extends LocalizableMessage {
  const BeaconFactCopiedMessage();

  @override
  String get toEn => 'Copied to clipboard.';

  @override
  String get toRu => 'Скопировано в буфер обмена.';
}
