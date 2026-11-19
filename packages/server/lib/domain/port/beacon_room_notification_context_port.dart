import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/beacon_notification_context.dart';

abstract class BeaconRoomNotificationContextPort {
  Future<BeaconKind> loadBeaconKind(String beaconId);

  Future<BeaconNotificationContext> loadContextForBeacon(String beaconId);
}
