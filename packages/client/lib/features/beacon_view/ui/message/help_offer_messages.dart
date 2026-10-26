import 'dart:async' show unawaited;

import 'package:get_it/get_it.dart';
import 'package:tentura/app/router/root_router.dart';
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

final class _ForwardActionLabel extends LocalizableMessage {
  const _ForwardActionLabel();

  @override
  String get toEn => 'Forward';

  @override
  String get toRu => 'Переслать';
}

/// After first help offer: snackbar text + action opens forward for this beacon.
final class HelpOfferedForwardNudgeMessage extends LocalizableActionMessage {
  const HelpOfferedForwardNudgeMessage(this.beaconId);

  final String beaconId;

  @override
  String get toEn => 'Help offered! Forward it to someone?';

  @override
  String get toRu => 'Помощь предложена! Переслать кому-нибудь?';

  @override
  LocalizableMessage get label => const _ForwardActionLabel();

  @override
  void Function() get onPressed => () {
    unawaited(
      GetIt.I<RootRouter>().push(ForwardBeaconRoute(beaconId: beaconId)),
    );
  };
}
