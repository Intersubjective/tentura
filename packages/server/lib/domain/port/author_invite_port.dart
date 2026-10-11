import 'package:tentura_server/domain/entity/author_invite.dart';

/// `beacon_author_invite` rows (Arch §2.2, §5): reads, row locks and status
/// transitions. Every write runs inside the caller's mutating unit.
abstract interface class AuthorInvitePort {
  /// The invite [inviteId], unlocked (used to find the locks to take).
  Future<AuthorInvite?> fetchById(String inviteId);

  /// The invite [inviteId], `FOR UPDATE` (lock-order step 4).
  Future<AuthorInvite?> lockById(String inviteId);

  /// The pending invite of [inviteeId] on [beaconId], unlocked.
  Future<AuthorInvite?> fetchPending({
    required String beaconId,
    required String inviteeId,
  });

  /// The pending invite of [inviteeId] on [beaconId], `FOR UPDATE`, when the
  /// inviter and the invitee are not blocked with each other.
  Future<AuthorInvite?> lockPendingUnblocked({
    required String beaconId,
    required String inviteeId,
  });

  /// Lock-order steps 1–2 (Arch §4.1): the global hierarchy lock, then the
  /// Post lock of [sourcePostId] when there is one.
  Future<void> lockScope(String? sourcePostId);

  /// Moves the pending invite [inviteId] to [status] and returns it, or
  /// returns null when it was not pending.
  Future<AuthorInvite?> resolve({
    required String inviteId,
    required AuthorInviteStatus status,
    required String? resolvedBy,
  });

  /// Withdraws every pending invite between [a] and [b] (either direction;
  /// block cleanup) and returns them.
  Future<List<AuthorInvite>> withdrawPendingBetween(String a, String b);

  /// Marks [edgeId] exempt from the ignored-contact sweep (a warm invite that
  /// reused an ordinary edge, Arch §2.5).
  Future<void> markEdgeSweepExempt(String edgeId);

  /// `contact_resolve_without_evidence` (m0241): resolves an unresolved
  /// contact on [edgeId] with no evidence.
  Future<bool> resolveContactWithoutEvidence(String edgeId);
}
