import 'package:tentura_server/domain/entity/post_bud.dart';

/// `beacon_author_invite.status` (Arch §2.2).
enum AuthorInviteStatus {
  pending(0),
  accepted(1),
  declined(2),
  withdrawn(3),
  expired(4),
  superseded(5);

  const AuthorInviteStatus(this.code);

  final int code;

  static AuthorInviteStatus fromCode(int code) => values.singleWhere(
    (e) => e.code == code,
    orElse: () =>
        throw ArgumentError.value(code, 'code', 'Unknown author invite status'),
  );
}

/// An author-confirmed invitation of a Post member into a Request budded from
/// the Post (Arch §2.2, D7).
final class AuthorInvite {
  const AuthorInvite({
    required this.id,
    required this.beaconId,
    required this.inviterId,
    required this.inviteeId,
    required this.sourcePostId,
    required this.forwardEdgeId,
    required this.warm,
    required this.status,
    this.note,
  });

  final String id;

  /// The child Request.
  final String beaconId;

  /// The recorded author confirmation (the child author at creation).
  final String inviterId;

  final String inviteeId;

  /// The parent Post; NULL for repair invites.
  final String? sourcePostId;

  /// The delivery edge inviter → invitee on the child.
  final String? forwardEdgeId;

  final bool warm;

  final AuthorInviteStatus status;

  /// Visible to the inviter and the invitee only.
  final String? note;

  bool get isPending => status == AuthorInviteStatus.pending;
}

/// Result of a later invite (`beaconAuthorInviteCreate`, Arch §3.3).
final class AuthorInviteCreateResult {
  const AuthorInviteCreateResult({required this.outcome, this.inviteId});

  final PostBudInviteOutcome outcome;

  /// Set when [outcome] is [PostBudInviteOutcome.invited].
  final String? inviteId;
}
