import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_post_lifetime.dart';

import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

/// Warns the author of an eligible open Post once, within
/// [BeaconPostLifetime.warnBefore] of its expiry.
@Singleton(order: 2)
final class PostExpiryWarningSweepCase {
  PostExpiryWarningSweepCase(this._beacons, this._intents, this._attention);

  final BeaconRepositoryPort _beacons;
  final AttentionIntentCase _intents;
  final TransactionalAttentionCase _attention;

  Future<int> runDue() async {
    const window = BeaconPostLifetime.warnBefore;
    final ids = await _beacons.postExpiryWarningCandidateIds(window: window);
    var recorded = 0;
    for (final id in ids) {
      await _attention.runAction<void>(
        actorUserId: null,
        action: (transaction) async {
          final authorId = await _beacons.lockPostForExpiryWarning(
            beaconId: id,
            window: window,
          );
          if (authorId == null) return;
          await transaction.record(
            await _intents.postExpiringSoon(
              beaconId: id,
              authorUserId: authorId,
            ),
          );
          recorded++;
        },
      );
    }
    return recorded;
  }
}
