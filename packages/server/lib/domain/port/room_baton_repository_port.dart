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

  /// Writes [candidate]'s answer and partner fields (§2.3 columns).
  /// `partner_responded_at` is stamped when the partner's answer changes.
  Future<void> saveCandidate(RoomBatonCandidate candidate);

  /// `block_hides`: either of [a] and [b] blocked the other.
  Future<bool> isPairBlocked({required String a, required String b});

  /// Opens a new answering round: the author is told again once everyone
  /// has answered.
  Future<void> clearAllAnsweredNotified(String batonId);

  /// Whether any candidate on [batonId] has not answered: still
  /// [BatonResponse.waiting], or `can_help` with a partner who has not
  /// answered yet.
  Future<bool> hasUnansweredCandidate(String batonId);

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

  /// The author's edit of who is asked, while collecting: inserts [add] as
  /// waiting, deletes [remove] and sets new tiers from [retier]. Answers of
  /// the people kept stay. Clears `all_answered_notified_at` when someone new
  /// is waiting, so the author is told again once everyone has answered.
  Future<void> updateCandidates({
    required String batonId,
    required List<({String userId, int tier})> add,
    required List<String> remove,
    required List<({String userId, int tier})> retier,
  });
}
