import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/commitment_query_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

@Singleton(order: 2)
final class DeadlineReminderSweepCase {
  DeadlineReminderSweepCase(
    this._beacons,
    this._commitments,
    this._intents,
    this._attention,
  );
  final BeaconRepositoryPort _beacons;
  final CommitmentQueryCase _commitments;
  final AttentionIntentCase _intents;
  final TransactionalAttentionCase _attention;
  Future<int> runDue({DateTime? now}) async {
    final instant = (now ?? DateTime.timestamp()).toUtc();
    final tomorrow = DateTime.utc(instant.year, instant.month, instant.day + 1);
    final following = tomorrow.add(const Duration(days: 1));
    final ids = await _beacons.deadlineReminderCandidateIds(
      nextUtcDayStart: tomorrow,
      followingUtcDayStart: following,
    );
    var recorded = 0;
    for (final id in ids) {
      await _attention.runAction<void>(
        actorUserId: null,
        action: (transaction) async {
          final beacon = await _beacons.lockOpenBeaconForDeadlineReminder(
            beaconId: id,
            nextUtcDayStart: tomorrow,
            followingUtcDayStart: following,
          );
          if (beacon?.endAt == null) return;
          final recipients = await _commitments.currentCommitterUserIds(id);
          if (recipients.isEmpty) return;
          await transaction.record(
            await _intents.deadlineReminder(
              beaconId: id,
              participantUserIds: recipients,
              deadline: beacon!.endAt!,
              sourceEventKey:
                  'deadline_reminder:$id:${tomorrow.toIso8601String()}',
            ),
          );
          recorded++;
        },
      );
    }
    return recorded;
  }
}
