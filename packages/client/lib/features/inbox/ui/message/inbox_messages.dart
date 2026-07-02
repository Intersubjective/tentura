import 'package:tentura_root/domain/entity/localizable.dart';

import '../../domain/enum.dart';

class InboxBeaconMovedMessage extends LocalizableMessage {
  const InboxBeaconMovedMessage({
    required this.beaconId,
    required this.toStatus,
    this.ownBeaconForward = false,
  });

  final String beaconId;
  final InboxItemStatus toStatus;

  /// After forwarding your own request, inbox moves to Watching; show a forward
  /// confirmation instead of the generic "moved to Watching" copy.
  final bool ownBeaconForward;

  /// Inbox primary tabs: 0 = Needs me, 1 = Watching. Rejected uses
  /// [navigatesToRejectedArchive] instead of tab index.
  int get tabIndex => switch (toStatus) {
        InboxItemStatus.watching => 1,
        _ => 0,
      };

  bool get navigatesToRejectedArchive =>
      toStatus == InboxItemStatus.rejected;

  @override
  String get toEn => switch (toStatus) {
        InboxItemStatus.watching =>
          ownBeaconForward ? 'Forwards sent' : 'Request moved to Watching',
        InboxItemStatus.rejected => 'Request moved to Rejected',
        _ => 'Request moved',
      };

  @override
  String get toRu => switch (toStatus) {
        InboxItemStatus.watching => ownBeaconForward
            ? 'Пересылки отправлены'
            : 'Запрос перемещён во вкладку «Наблюдаю»',
        InboxItemStatus.rejected =>
          'Запрос перемещён во вкладку «Отклонённые»',
        _ => 'Запрос перемещён',
      };
}
