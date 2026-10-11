import 'package:tentura_server/domain/entity/post_bud_invite_candidate.dart';
import 'package:tentura_server/domain/entity/post_parent_stage.dart';

/// Per-invitee outcome of budding a Request from a Post (plan §0, Arch §4.2).
/// One enum for the server and the client; the wire value is [name].
///
/// In `postBudInviteCandidates`, [invited] means «can be invited now».
enum PostBudInviteOutcome {
  invited,
  notEligible,
  alreadyInvited,
  recipientPaused,
  blocked;

  static PostBudInviteOutcome fromReason(PostBudInviteReason reason) =>
      switch (reason) {
        PostBudInviteReason.eligible => invited,
        PostBudInviteReason.notMember => notEligible,
        PostBudInviteReason.notVisible => notEligible,
        PostBudInviteReason.blocked => blocked,
        PostBudInviteReason.recipientPaused => recipientPaused,
        PostBudInviteReason.alreadyInvited => alreadyInvited,
      };

  static PostBudInviteOutcome fromName(String name) => values.singleWhere(
    (e) => e.name == name,
    orElse: () =>
        throw ArgumentError.value(name, 'name', 'Unknown bud invite outcome'),
  );
}

/// One invitee the budder picked, with an optional note (Arch §4.2).
final class PostBudInvitee {
  const PostBudInvitee({required this.userId, this.note});

  final String userId;

  /// Visible to the inviter and the invitee only; never copied into the
  /// delivery edge note.
  final String? note;
}

/// Result of `beaconBudFromPost`: the stored `bud_result`, returned verbatim
/// on replay.
final class PostBudResult {
  const PostBudResult({
    required this.outcome,
    required this.childBeaconId,
    required this.invitees,
  });

  /// Reads a stored `bud_result` (`PostBudResultJson`).
  factory PostBudResult.fromJson(Map<String, Object?> json) => PostBudResult(
    outcome: json[PostBudResultJson.outcome]! as String,
    childBeaconId: json[PostBudResultJson.childBeaconId] as String?,
    invitees: [
      for (final raw
          in (json[PostBudResultJson.invitees] as List?) ?? const <Object?>[])
        PostBudInviteeResult.fromJson((raw! as Map).cast<String, Object?>()),
    ],
  );

  /// `created` or `alreadyPromoted` (`PostBudResultJson`).
  final String outcome;

  final String? childBeaconId;

  final List<PostBudInviteeResult> invitees;
}

/// One invitee of a [PostBudResult].
final class PostBudInviteeResult {
  const PostBudInviteeResult({required this.userId, required this.outcome});

  factory PostBudInviteeResult.fromJson(Map<String, Object?> json) =>
      PostBudInviteeResult(
        userId: json[userIdKey]! as String,
        outcome: PostBudInviteOutcome.fromName(json[outcomeKey]! as String),
      );

  static const userIdKey = 'userId';
  static const outcomeKey = 'outcome';

  final String userId;

  final PostBudInviteOutcome outcome;

  Map<String, Object?> toJson() => {
    userIdKey: userId,
    outcomeKey: outcome.name,
  };
}
