import 'package:freezed_annotation/freezed_annotation.dart';

import 'post_bud_invite_outcome.dart';

part 'post_bud_invite_candidate.freezed.dart';

/// A Post member the budder may invite to the new Request (plan C3).
@freezed
abstract class PostBudInviteCandidate with _$PostBudInviteCandidate {
  const factory PostBudInviteCandidate({
    required String userId,

    /// The member wrote in the Post or is its author.
    required bool warm,

    /// [PostBudInviteOutcome.invited] means the member can be invited now.
    required PostBudInviteOutcome outcome,

    /// Ticked by default in the invite step.
    required bool pretick,

    /// The member has written in the Post (writers are listed first).
    required bool hasWritten,

    /// «через X»: who brought this member into the Post, when the budder may
    /// not know them.
    String? viaUserId,
  }) = _PostBudInviteCandidate;

  const PostBudInviteCandidate._();

  bool get isInvitable => outcome == PostBudInviteOutcome.invited;
}
