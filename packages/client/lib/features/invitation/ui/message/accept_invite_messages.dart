import 'package:tentura_root/domain/entity/localizable.dart';

final class InviteNoLongerValidMessage extends LocalizableMessage {
  const InviteNoLongerValidMessage();

  @override
  String get toEn => 'This invite is no longer valid.';

  @override
  String get toRu => 'Это приглашение больше недействительно.';
}

final class InviteOwnInviteMessage extends LocalizableMessage {
  const InviteOwnInviteMessage();

  @override
  String get toEn => 'This is your own invite link.';

  @override
  String get toRu => 'Это ваша собственная ссылка-приглашение.';
}

final class InviteAlreadyFriendsMessage extends LocalizableMessage {
  const InviteAlreadyFriendsMessage();

  @override
  String get toEn => 'You are already connected with this person.';

  @override
  String get toRu => 'Вы уже связаны с этим человеком.';
}

final class InviteAcceptedMessage extends LocalizableMessage {
  const InviteAcceptedMessage();

  @override
  String get toEn => 'Invitation accepted.';

  @override
  String get toRu => 'Приглашение принято.';
}

final class InviteInvalidCodeMessage extends LocalizableMessage {
  const InviteInvalidCodeMessage();

  @override
  String get toEn => 'This invite code is not valid.';

  @override
  String get toRu => 'Этот код приглашения недействителен.';
}
