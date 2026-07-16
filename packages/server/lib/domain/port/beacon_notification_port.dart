import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/entity/beacon_notification_intent.dart';

abstract class BeaconNotificationPort {
  /// Compatibility path used until each producer moves to transactional
  /// receipt recording.
  Future<void> dispatch(BeaconNotificationIntent intent);

  /// Best-effort channel work for receipts that have already committed.
  Future<void> handOffChannels(List<AttentionChannelDecision> decisions);
}
