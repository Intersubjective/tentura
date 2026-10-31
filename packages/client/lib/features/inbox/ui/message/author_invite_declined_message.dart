import 'package:tentura/ui/message/action_message_base.dart';

/// After «Не смогу» on an author invite: says so and offers Undo, which asks
/// the server to put the invitation back while it is still valid.
final class AuthorInviteDeclinedMessage extends LocalizableUndoMessage {
  const AuthorInviteDeclinedMessage(this.onUndo);

  final void Function() onUndo;

  @override
  String get toEn => "You can't make it. The invitation is declined.";

  @override
  String get toRu => 'Вы отказались от приглашения.';

  @override
  LocalizableMessage get label => const _UndoLabel();

  @override
  void Function() get onPressed => onUndo;
}

final class _UndoLabel extends LocalizableMessage {
  const _UndoLabel();

  @override
  String get toEn => 'Undo';

  @override
  String get toRu => 'Отменить';
}
