import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/attention_channel_delivery_port.dart';
import 'package:tentura_server/domain/port/beacon_notification_port.dart';

@LazySingleton()
class AttentionChannelDeliveryCase {
  const AttentionChannelDeliveryCase(this._deliveries, this._channels);

  final AttentionChannelDeliveryPort _deliveries;
  final BeaconNotificationPort _channels;

  Future<void> runDue({required String workerId, required DateTime now}) async {
    final jobs = await _deliveries.claimDue(
      workerId: workerId,
      now: now,
      limit: 50,
    );
    for (final job in jobs) {
      try {
        await _channels.handOffChannels([job.decision]);
        await _deliveries.markDelivered(id: job.id, workerId: workerId);
      } on Object catch (error) {
        await _deliveries.retryOrDeadLetter(
          id: job.id,
          workerId: workerId,
          now: now,
          error: error,
        );
      }
    }
  }
}
