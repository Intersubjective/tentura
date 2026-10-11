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
}
