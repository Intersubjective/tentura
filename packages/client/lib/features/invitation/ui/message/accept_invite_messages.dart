import 'dart:async' show unawaited;

import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/ui/message/action_message_base.dart';

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

/// Opening your own invite link while signed in (#272): say plainly that it
/// is yours, how to use it, and how to try it out; offer to copy it.
final class InviteOwnInviteLinkMessage extends LocalizableActionMessage {
  const InviteOwnInviteLinkMessage({required this.code});

  /// Normalized invite code, e.g. `I0123abcd`.
  final String code;

  @override
  String get toEn =>
      'This is your own invite link. Send it to the person you want to '
      'invite. To try it yourself, open it in a private browser window.';

  @override
  String get toRu =>
      'Это ваша собственная ссылка-приглашение. Отправьте её тому, кого '
      'хотите пригласить. Чтобы проверить её самим, откройте её в приватном '
      'окне браузера.';

  @override
  LocalizableMessage get label => const _CopyInviteLinkActionLabel();

  @override
  void Function() get onPressed => () {
    unawaited(
      Clipboard.setData(ClipboardData(text: inviteShareUri(code).toString())),
    );
  };
}

final class _CopyInviteLinkActionLabel extends LocalizableMessage {
  const _CopyInviteLinkActionLabel();

  @override
  String get toEn => 'Copy link';

  @override
  String get toRu => 'Копировать ссылку';
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

final class InviteTrailingDashHintMessage extends LocalizableMessage {
  const InviteTrailingDashHintMessage();

  @override
  String get toEn =>
      'This invite link ends with an extra dash. Remove the trailing "-" and try again.';

  @override
  String get toRu =>
      'В конце ссылки на приглашение лишний дефис. Удалите «-» в конце и попробуйте снова.';
}

final class _OpenPostActionLabel extends LocalizableMessage {
  const _OpenPostActionLabel();

  @override
  String get toEn => 'Open post';

  @override
  String get toRu => 'Открыть пост';
}

final class _OpenBeaconActionLabel extends LocalizableMessage {
  const _OpenBeaconActionLabel();

  @override
  String get toEn => 'Open request';

  @override
  String get toRu => 'Открыть запрос';
}

/// Shown after accepting a beacon-bearing invite.
final class BeaconInviteAcceptedMessage extends LocalizableActionMessage {
  const BeaconInviteAcceptedMessage({
    required this.inviterName,
    required this.beaconId,
    required this.beaconTitle,
    this.isPost = false,
  });

  final String inviterName;
  final String beaconId;
  final String beaconTitle;

  /// The invite shared a Post (#501): name the post, not a request.
  final bool isPost;

  @override
  String get toEn {
    final who = inviterName.isEmpty ? 'Someone' : inviterName;
    if (isPost) {
      return beaconTitle.isEmpty
          ? '$who shared a post with you.'
          : '$who shared the post «$beaconTitle» with you.';
    }
    final title = beaconTitle.isEmpty ? 'a request' : beaconTitle;
    return "$who shared $title with you. It's in your Inbox.";
  }

  @override
  String get toRu {
    final who = inviterName.isEmpty ? 'Кто-то' : inviterName;
    if (isPost) {
      return beaconTitle.isEmpty
          ? '$who поделился(ась) с вами постом.'
          : '$who поделился(ась) с вами постом «$beaconTitle».';
    }
    final title = beaconTitle.isEmpty ? 'запрос' : beaconTitle;
    return '$who поделился(ась) «$title» с вами. Он в ваших входящих.';
  }

  @override
  LocalizableMessage get label =>
      isPost ? const _OpenPostActionLabel() : const _OpenBeaconActionLabel();

  @override
  void Function() get onPressed => () {
    unawaited(
      GetIt.I<RootRouter>().push(BeaconViewRoute(id: beaconId)),
    );
  };
}
