import 'package:tentura/ui/message/action_message_base.dart';

final class BackupOfferSentMessage extends LocalizableMessage {
  const BackupOfferSentMessage();

  @override
  String get toEn =>
      'Your backup offer was sent to the author. '
      'They may contact you if more help is needed.';

  @override
  String get toRu =>
      'Ваше предложение помощи как запасного варианта отправлено автору. '
      'Он может обратиться к вам, если понадобится больше помощи.';
}

final class MovedToInboxMessage extends LocalizableMessage {
  const MovedToInboxMessage();

  @override
  String get toEn =>
      "Offer withdrawn. You'll still get updates on it under Following.";

  @override
  String get toRu =>
      'Предложение отозвано. Обновления по нему останутся во вкладке «Слежу».';
}

/// #734: after Accept on someone's offer, on the screen where it was taken.
final class HelpOfferAcceptedMessage extends LocalizableMessage {
  const HelpOfferAcceptedMessage(this.name);

  /// The helper's shown name; empty when unknown.
  final String name;

  @override
  String get toEn =>
      name.isEmpty ? 'Offer accepted' : '$name admitted to the discussion';

  @override
  String get toRu =>
      name.isEmpty ? 'Предложение принято' : '$name теперь в обсуждении';
}

/// #734: after Decline on someone's offer; they are told, with the reason.
final class HelpOfferDeclinedMessage extends LocalizableMessage {
  const HelpOfferDeclinedMessage(this.name);

  /// The offerer's shown name; empty when unknown.
  final String name;

  @override
  String get toEn =>
      name.isEmpty ? 'Offer declined' : 'Offer declined — $name was told';

  @override
  String get toRu => name.isEmpty
      ? 'Предложение отклонено'
      : 'Предложение отклонено — $name получит уведомление';
}

/// #734: after «Позвать» on the People tab sent an invitation.
final class AuthorInviteSentMessage extends LocalizableMessage {
  const AuthorInviteSentMessage(this.name);

  /// The invitee's shown name; empty when unknown.
  final String name;

  @override
  String get toEn =>
      name.isEmpty ? 'Invitation sent' : 'Invitation sent to $name';

  @override
  String get toRu =>
      name.isEmpty ? 'Приглашение отправлено' : 'Приглашение отправлено: $name';
}

/// After «Decline remaining offers» (#268).
final class RemainingOffersDeclinedMessage extends LocalizableMessage {
  const RemainingOffersDeclinedMessage(this.count);

  final int count;

  @override
  String get toEn => count == 0
      ? 'No offers were waiting.'
      : count == 1
      ? '1 offer declined.'
      : '$count offers declined.';

  @override
  String get toRu => count == 0
      ? 'Ожидающих предложений не было.'
      : 'Отклонено предложений: $count.';
}

/// #527: after a first help offer, a plain receipt that says what happens
/// next. No Forward action: the page keeps its own Forward, and a second one
/// here read as "we don't need you, pass it on".
final class HelpOfferSentMessage extends LocalizableMessage {
  const HelpOfferSentMessage(this.authorName);

  /// The author's shown name; empty when unknown.
  final String authorName;

  @override
  String get toEn => authorName.isEmpty
      ? "Offer sent to the author. You'll be notified when they answer."
      : "Offer sent to $authorName. You'll be notified when they answer.";

  @override
  String get toRu => authorName.isEmpty
      ? 'Предложение отправлено автору. Вы получите уведомление, когда '
            'автор ответит.'
      : 'Предложение отправлено: $authorName. Вы получите уведомление, '
            'когда автор ответит.';
}
