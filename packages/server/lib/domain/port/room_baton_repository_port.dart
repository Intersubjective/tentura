import 'package:tentura_server/domain/entity/room_baton.dart';

/// «Who'll take it?» (baton) storage — plan §2.2/B4
/// (`docs/plans/baton-who-takes-it-plan.md`). Raw SQL over m0219's tables;
/// no Drift table classes (plan §2.1).
abstract interface class RoomBatonRepositoryPort {
  /// `null` when the message has no live (non-cancelled) baton.
  Future<RoomBaton?> getLiveBatonForMessage(String messageId);

  Future<RoomBaton?> getById(String batonId);

  Future<List<RoomBatonCandidate>> getCandidates(String batonId);

  /// Inserts the baton row and its candidates in one call.
  Future<RoomBaton> create({
    required String id,
    required String messageId,
    required String beaconId,
    required String authorId,
    required List<({String userId, int tier})> candidates,
  });

  Future<void> updateCandidateResponse({
    required String batonId,
    required String userId,
    required BatonResponse response,
    required DateTime respondedAt,
  });

  /// Whether any candidate on [batonId] is still [BatonResponse.waiting].
  Future<bool> hasWaitingCandidate(String batonId);

  /// Sets `all_answered_notified_at` if it is still null. Returns `true` the
  /// first time (the caller should dispatch the `batonAllAnswered` receipt),
  /// `false` on every later call (already notified).
  Future<bool> markAllAnsweredNotifiedIfUnset({
    required String batonId,
    required DateTime at,
  });

  Future<void> select({
    required String batonId,
    required String takerId,
    required BatonSelectionMode mode,
    required DateTime resolvedAt,
  });

  Future<void> cancel({required String batonId, required DateTime resolvedAt});
}
