import 'package:tentura_server/domain/entity/beacon_notification_context.dart';

abstract class BeaconRoomNotificationContextPort {
  Future<BeaconNotificationContext> loadContextForBeacon(String beaconId);
}
