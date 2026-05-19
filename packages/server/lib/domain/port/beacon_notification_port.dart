import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';

abstract class BeaconNotificationPort {
  Future<void> dispatch(BeaconNotificationIntent intent);
}
