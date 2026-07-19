import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/port/attention_expiry_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/port/review_finalization_port.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/utils/id.dart';

@Singleton(order: 3)
class AttentionExpirySweepCase {
  const AttentionExpirySweepCase(
    this._expiryRepository,
    this._reviewFinalization,
    this._intents,
    this._attention,
  );

  final AttentionExpiryRepositoryPort _expiryRepository;
  final ReviewFinalizationPort _reviewFinalization;
  final AttentionIntentCase _intents;
  final TransactionalAttentionCase _attention;

  Future<int> runDue({DateTime? now}) async {
    final beaconIds = await _expiryRepository.lockExpiredReviewWindowBeaconIds(
      now ?? DateTime.timestamp(),
    );
    var closed = 0;
    for (final beaconId in beaconIds) {
      try {
        await _attention.runAction<void>(
          actorUserId: null,
          action: (transaction) async {
            final intent = await _intents.requestStatusChanged(
              beaconId: beaconId,
              fromStatus: BeaconStatus.reviewOpen.name,
              toStatus: BeaconStatus.closed.name,
              actorUserId: null,
              sourceEventKey: 'request_status:${generateId('A')}',
            );
            final didClose = await _reviewFinalization.closeAndFinalize(
              beaconId,
              reason: BeaconLifecycleChangeReason.reviewExpired,
            );
            if (didClose) {
              await transaction.record(intent);
              closed++;
            }
          },
        );
      } catch (e, st) {
        // Per-beacon isolation: one failure must not wedge the batch.
        // ignore: avoid_print
        print('AttentionExpirySweepCase: failed $beaconId: $e\n$st');
      }
    }
    return closed;
  }
}
