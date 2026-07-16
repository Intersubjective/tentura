import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/port/attention_expiry_repository_port.dart';
import 'package:tentura_server/domain/port/evaluation_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';
import 'package:tentura_server/utils/id.dart';

@Singleton(order: 1)
class AttentionExpirySweepCase {
  const AttentionExpirySweepCase(
    this._expiryRepository,
    this._evaluationRepository,
    this._intents,
    this._attention,
    this._env,
  );

  final AttentionExpiryRepositoryPort _expiryRepository;
  final EvaluationRepositoryPort _evaluationRepository;
  final AttentionIntentCase _intents;
  final TransactionalAttentionCase _attention;
  final Env _env;

  Future<int> runDue({DateTime? now}) async {
    if (!_env.attentionV1NewProducersEnabled) return 0;
    return _attention.runAction<int>(
      actorUserId: null,
      action: (transaction) async {
        final beaconIds = await _expiryRepository
            .lockExpiredReviewWindowBeaconIds(now ?? DateTime.timestamp());
        for (final beaconId in beaconIds) {
          final intent = await _intents.requestStatusChanged(
            beaconId: beaconId,
            fromStatus: BeaconStatus.reviewOpen.name,
            toStatus: BeaconStatus.closed.name,
            actorUserId: null,
            sourceEventKey: 'request_status:${generateId('A')}',
          );
          await _evaluationRepository.closeBeaconReviewWindow(
            beaconId,
            reason: BeaconLifecycleChangeReason.reviewExpired,
          );
          await transaction.record(intent);
        }
        return beaconIds.length;
      },
    );
  }
}
