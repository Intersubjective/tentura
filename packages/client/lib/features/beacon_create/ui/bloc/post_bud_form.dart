import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/post_bud_result.dart';
import 'package:tentura/features/forward/ui/bloc/forward_state.dart'
    show ForwardState;

part 'post_bud_form.freezed.dart';

/// The Post-only part of the Request form when it buds a Request from a Post
/// message (plan D1): where it comes from and whether to close the Post. Whom
/// to invite is the invite step's Forward picker selection.
@Freezed(makeCollectionsUnmodifiable: false)
abstract class PostBudForm with _$PostBudForm {
  const factory PostBudForm({
    required String postId,
    required String sourceMessageId,

    /// One id per screen session: a repeated submit replays the same bud.
    required String clientCommandId,

    /// The Post kept forwarding off; the Request will be forwardable.
    @Default(false) bool postForwardingClosed,

    /// Who started the Post: only they may close it (#666).
    @Default('') String postAuthorId,

    /// The budder's own choice; null follows [closePostByDefault].
    bool? closePostChoice,

    /// The Post's readable facts the budder may bring along.
    @Default(<BeaconFactCard>[]) List<BeaconFactCard> facts,

    /// Ticked fact ids, in list order; nothing is ticked at first.
    @Default(<String>[]) List<String> factIds,
  }) = _PostBudForm;

  const PostBudForm._();

  /// Only the Post's author may close it (#666); [invite] is the invite
  /// step's picker state, which knows whether the budder is that author.
  bool canClosePost(ForwardState invite) => invite.viewerIsAuthor;

  /// «Закрыть пост…» is on by default when the Post has at most two members
  /// or every member is ticked (one who cannot be invited never is). Off while
  /// the membership is unknown, and never offered to anyone but the author.
  bool closePostByDefault(ForwardState invite) {
    final memberCount = invite.postMemberCount;
    if (!canClosePost(invite) || memberCount == 0) return false;
    if (memberCount <= 2) return true;
    return invite.candidates.length == memberCount - 1 &&
        invite.candidates.every((c) => invite.selectedIds.contains(c.id));
  }

  bool closePost(ForwardState invite) =>
      canClosePost(invite) && (closePostChoice ?? closePostByDefault(invite));

  /// The ticked members, in list order, with their trimmed notes.
  List<PostBudInvitee> invitees(ForwardState invite) => [
    for (final c in invite.candidates)
      if (invite.selectedIds.contains(c.id))
        PostBudInvitee(
          userId: c.id,
          note: switch ((invite.perRecipientNotes[c.id] ?? '').trim()) {
            '' => null,
            final note => note,
          },
        ),
  ];
}
