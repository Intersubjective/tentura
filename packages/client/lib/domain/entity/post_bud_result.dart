import 'package:freezed_annotation/freezed_annotation.dart';

import 'post_bud_invite_outcome.dart';

part 'post_bud_result.freezed.dart';

/// Whether `beaconBudFromPost` created the child or found it already budded
/// from the same source message.
enum PostBudOutcome {
  created,
  alreadyPromoted;

  static PostBudOutcome fromWire(String raw) =>
      values.firstWhere((o) => o.name == raw, orElse: () => created);
}

/// One invitee the budder picked, with an optional note (plan D1).
@freezed
abstract class PostBudInvitee with _$PostBudInvitee {
  const factory PostBudInvitee({
    required String userId,
    String? note,
  }) = _PostBudInvitee;
}

@freezed
abstract class PostBudInviteeResult with _$PostBudInviteeResult {
  const factory PostBudInviteeResult({
    required String userId,
    required PostBudInviteOutcome outcome,
  }) = _PostBudInviteeResult;
}

/// Result of budding a Request from a Post (plan C3, Arch §4.2).
@freezed
abstract class PostBudResult with _$PostBudResult {
  const factory PostBudResult({
    required PostBudOutcome outcome,
    String? childBeaconId,
    @Default(<PostBudInviteeResult>[]) List<PostBudInviteeResult> invitees,
  }) = _PostBudResult;

  const PostBudResult._();

  /// Picked invitees the server did not invite (for `postBudNotInvitedSnack`).
  List<String> get notInvitedUserIds => [
    for (final i in invitees)
      if (i.outcome != PostBudInviteOutcome.invited) i.userId,
  ];
}
