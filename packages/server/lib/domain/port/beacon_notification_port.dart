import 'package:tentura_server/domain/attention/attention_models.dart';

abstract class BeaconNotificationPort {
  /// Best-effort channel work for receipts that have already committed.
  Future<void> handOffChannels(List<AttentionChannelDecision> decisions);
}
