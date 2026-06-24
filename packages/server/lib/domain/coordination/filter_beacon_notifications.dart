import 'package:tentura_server/domain/entity/notification_outbox_item_entity.dart';
import 'package:tentura_server/domain/port/beacon_access_guard.dart';

const kBeaconUnavailableNotificationTitle = 'Beacon no longer available';
const kBeaconUnavailableNotificationBody =
    'This beacon was deleted or is no longer visible to you.';

/// Drops or tombstones notification rows whose beacon content is no longer
/// readable at fetch/send time (ADR 0008 §5).
Future<List<NotificationOutboxItemEntity>> filterBeaconNotifications({
  required BeaconAccessGuard guard,
  required String viewerId,
  required List<NotificationOutboxItemEntity> items,
}) async {
  if (items.isEmpty) return items;

  final out = <NotificationOutboxItemEntity>[];
  for (final item in items) {
    final beaconId = item.beaconId;
    if (beaconId == null || beaconId.isEmpty) {
      out.add(item);
      continue;
    }

    if (await guard.canReadContent(beaconId: beaconId, viewerId: viewerId)) {
      out.add(item);
      continue;
    }

    if (await guard.canReadTombstone(beaconId: beaconId, viewerId: viewerId)) {
      out.add(
        item.copyWith(
          title: kBeaconUnavailableNotificationTitle,
          body: kBeaconUnavailableNotificationBody,
        ),
      );
    }
  }
  return out;
}
