import 'package:tentura_server/domain/entity/post_bud_invite_candidate.dart';

/// Membership and invite facts for budding a Request from a Post
/// (Arch §2.1, §3.3).
abstract interface class PostBudPort {
  /// The effective Post member set `E(P)`: the author plus admitted members,
  /// minus users blocked with the Post author. Empty for a Request.
  Future<List<String>> effectiveMemberIds(String postId);

  /// Every member of `E(P) \ {budderId}` with its invite facts. A cold member
  /// (not warm) that is not forward-visible to the budder is
  /// [PostBudInviteReason.notVisible]; warm members skip the visibility gate.
  Future<List<PostBudInviteCandidate>> inviteCandidates({
    required String postId,
    required String budderId,
  });

  /// Inserts a pending author invite into [beaconId] (Arch §2.2) and returns
  /// its id. `arrival_post_edge_id` is the invitee's latest active inbound
  /// edge on [sourcePostId] (NULL for the Post author). Returns null when a
  /// pending invite already holds the slot (N5 or the per-Request pending
  /// index): nothing is inserted.
  Future<String?> insertInvite({
    required String beaconId,
    required String inviterId,
    required String inviteeId,
    required String sourcePostId,
    required String? forwardEdgeId,
    required bool warm,
    String? note,
  });

  /// A later invite of [inviteeId] into the budded Request [childId] by its
  /// author [inviterId] (Arch §3.3): the same facts as [inviteCandidates],
  /// evaluated for effective Post members whose admission predates the Request.
  /// Null when [inviteeId] is outside that audience. A block with [inviterId]
  /// is [PostBudInviteReason.blocked]; a pending invite on [childId] or for
  /// the same inviter and Post is [PostBudInviteReason.alreadyInvited].
  Future<PostBudInviteCandidate?> laterInviteCandidate({
    required String childId,
    required String postId,
    required String inviterId,
    required String inviteeId,
  });

  /// Post members eligible to be considered for a later invite to [childId],
  /// ordered by id. Empty unless [authorId] is the Request's author.
  Future<List<String>> observerIdsForAuthor({
    required String childId,
    required String authorId,
  });
}
