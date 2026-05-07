import 'dart:async' show unawaited;

import 'package:get_it/get_it.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/ui/message/action_message_base.dart';

final class MovedToInboxMessage extends LocalizableMessage {
  const MovedToInboxMessage();

  @override
  String get toEn =>
      'Commitment withdrawn — the beacon is in Watching (not in Needs me).';

  @override
  String get toRu =>
      'Обязательство отозвано — маяк в «Наблюдении», не в «Нужно мне».';
}

final class _ForwardActionLabel extends LocalizableMessage {
  const _ForwardActionLabel();

  @override
  String get toEn => 'Forward';

  @override
  String get toRu => 'Переслать';
}

/// After first commit: snackbar text + action opens forward for this beacon.
final class CommittedForwardNudgeMessage extends LocalizableActionMessage {
  const CommittedForwardNudgeMessage(this.beaconId);

  final String beaconId;

  @override
  String get toEn => 'Committed! Forward it to someone?';

  @override
  String get toRu => 'Закоммичено! Переслать кому-нибудь?';

  @override
  LocalizableMessage get label => const _ForwardActionLabel();

  @override
  void Function() get onPressed => () {
    unawaited(
      GetIt.I<RootRouter>().pushPath('$kPathForwardBeacon/$beaconId'),
    );
  };
}
