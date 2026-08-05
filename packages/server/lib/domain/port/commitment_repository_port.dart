import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';

abstract class CommitmentRepositoryPort {
  /// Пишет событие И пересчитывает проекцию `beacon_help_offer.stake_state`
  /// в одной транзакции (см. §2.5). Другого места, где проекция меняется, нет.
  Future<void> record({
    required String beaconId,
    required String userId,
    required String actorUserId,
    required CommitmentEventKind kind,
    String? reason,
  });

  /// Все события запроса, сгруппированные по userId, отсортированные по seq ASC.
  Future<Map<String, List<CommitmentEvent>>> eventsByUser(String beaconId);

  Future<List<CommitmentEvent>> eventsForPair({
    required String beaconId,
    required String userId,
  });
}
