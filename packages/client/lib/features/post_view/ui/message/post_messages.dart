import 'package:tentura/ui/message/action_message_base.dart';

/// After «Выйти из разговора»: the Post is gone from the conversations, and
/// «Вернуть» brings the viewer back into it.
final class PostLeftMessage extends LocalizableActionMessage {
  const PostLeftMessage({required this.onPressed});

  @override
  String get toEn => 'You left the conversation';

  @override
  String get toRu => 'Вы вышли из разговора';

  @override
  final void Function() onPressed;

  @override
  LocalizableMessage get label => const _PostLeftUndoLabel();
}

final class _PostLeftUndoLabel extends LocalizableMessage {
  const _PostLeftUndoLabel();

  @override
  String get toEn => 'Undo';

  @override
  String get toRu => 'Вернуть';
}
