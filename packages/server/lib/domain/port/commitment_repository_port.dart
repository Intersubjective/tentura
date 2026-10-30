import 'package:tentura_server/domain/commitment/commitment_event.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';

abstract class CommitmentRepositoryPort {
  /// Пишет событие И пересчитывает проекцию `beacon_help_offer.stake_state`
  /// в одной транзакции (см. §2.5). Другого места, где проекция меняется, нет.
  ///
  /// [actorUserId] is recorded as data. The write runs in a mutating unit for
  /// [mutatingUserId] (default: [actorUserId]); pass the authenticated actor
  /// when the recorded actor is someone else (Arch §5.3: the confirming author
  /// of an invite accept), so the call joins the outer unit instead of
  /// opening a nested one for a different actor.
  Future<void> record({
    required String beaconId,
    required String userId,
    required String actorUserId,
    required CommitmentEventKind kind,
    String? reason,
    String? mutatingUserId,
  });

  /// Все события запроса, сгруппированные по userId, отсортированные по seq ASC.
  Future<Map<String, List<CommitmentEvent>>> eventsByUser(String beaconId);

  /// [eventsByUser] of each of [beaconIds] with events, keyed by beacon id,
  /// read in one query.
  Future<Map<String, Map<String, List<CommitmentEvent>>>>
  eventsByUserByBeaconIds(Iterable<String> beaconIds);

  Future<List<CommitmentEvent>> eventsForPair({
    required String beaconId,
    required String userId,
  });
}
