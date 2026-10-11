/// Why a Post member may or may not be invited into a Request budded from the
/// Post (plan §0). [code] is the SQL `reason smallint` of
/// `post_bud_invite_facts`; [notVisible] is decided in Dart.
enum PostBudInviteReason {
  eligible(0),
  notMember(1),
  blocked(2),
  notVisible(3),
  recipientPaused(4),
  alreadyInvited(5);

  const PostBudInviteReason(this.code);

  final int code;

  static PostBudInviteReason fromCode(int code) => values.singleWhere(
    (e) => e.code == code,
    orElse: () =>
        throw ArgumentError.value(code, 'code', 'Unknown bud invite reason'),
  );
}

/// One member of `E(P) \ {budder}` as an invite candidate (Arch §3.3).
final class PostBudInviteCandidate {
  const PostBudInviteCandidate({
    required this.userId,
    required this.warm,
    required this.reason,
    required this.hasWritten,
    required this.pretick,
    this.viaUserId,
  });

  final String userId;

  /// First responder in the Post, or the Post author.
  final bool warm;

  final PostBudInviteReason reason;

  /// Authored a non-system message in the Post.
  final bool hasWritten;

  /// The budder @mentioned them, or they replied to the budder (D5).
  final bool pretick;

  /// Sender of their latest active inbound forward edge on the Post.
  final String? viaUserId;

  bool get isEligible => reason == PostBudInviteReason.eligible;
}
