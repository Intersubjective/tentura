import 'package:tentura_root/domain/entity/localizable.dart';

import '../../domain/enum.dart';

class InboxBeaconMovedMessage extends LocalizableMessage {
  const InboxBeaconMovedMessage({
    required this.beaconId,
    required this.toStatus,
  });

  final String beaconId;
  final InboxItemStatus toStatus;

  int get tabIndex => switch (toStatus) {
        InboxItemStatus.watching => 1,
        InboxItemStatus.rejected => 2,
        _ => 0,
      };

  @override
  String get toEn => switch (toStatus) {
        InboxItemStatus.watching => 'Beacon moved to Watching',
        InboxItemStatus.rejected => 'Beacon moved to Rejected',
        _ => 'Beacon moved',
      };

  @override
  String get toRu => switch (toStatus) {
        InboxItemStatus.watching =>
          'Маяк перемещён во вкладку «Наблюдаю»',
        InboxItemStatus.rejected =>
          'Маяк перемещён во вкладку «Отклонённые»',
        _ => 'Маяк перемещён',
      };
}
