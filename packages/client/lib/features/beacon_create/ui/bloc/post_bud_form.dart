import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/post_bud_invite_candidate.dart';
import 'package:tentura/domain/entity/post_bud_result.dart';
import 'package:tentura/domain/entity/profile.dart';

part 'post_bud_form.freezed.dart';

/// The Post-only part of the Request form when it buds a Request from a Post
/// message (plan D1): where it comes from and whom to invite.
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

    @Default(false) bool candidatesLoaded,

    /// The last members load failed; cleared while a retry runs.
    @Default(false) bool candidatesFailed,

    /// Every member of `E(P)` but the budder, as the server sent them.
    @Default(<PostBudInviteCandidate>[])
    List<PostBudInviteCandidate> candidates,

    /// Candidates and «через X» users by id.
    @Default(<String, Profile>{}) Map<String, Profile> profiles,

    @Default(<String>{}) Set<String> selectedIds,

    /// Per-invitee note, keyed by user id.
    @Default(<String, String>{}) Map<String, String> notes,

    /// The budder's own choice; null follows [closePostByDefault].
    bool? closePostChoice,
  }) = _PostBudForm;

  const PostBudForm._();

  /// Members the budder can invite now, writers first. Ineligible members are
  /// not offered at all.
  List<PostBudInviteCandidate> get invitable {
    final eligible = [
      for (final c in candidates)
        if (c.isInvitable) c,
    ];
    return [
      for (final c in eligible)
        if (c.hasWritten) c,
      for (final c in eligible)
        if (!c.hasWritten) c,
    ];
  }

  /// Size of `E(P)`: the candidates plus the budder.
  int get memberCount => candidates.length + 1;

  /// Only the Post's author may close it (#666). The candidates are every
  /// member but the budder, so the author is among them exactly when the
  /// budder is someone else. Unknown (false) until they load; the server
  /// refuses a close from anyone else either way.
  bool get canClosePost =>
      candidatesLoaded &&
      postAuthorId.isNotEmpty &&
      !candidates.any((c) => c.userId == postAuthorId);

  /// «Закрыть пост…» is on by default when the Post has at most two members
  /// or every member is ticked (one who cannot be invited never is). Off while
  /// the membership is unknown, and never offered to anyone but the author.
  bool get closePostByDefault {
    if (!canClosePost) return false;
    if (memberCount <= 2) return true;
    return candidates.every((c) => selectedIds.contains(c.userId));
  }

  bool get closePost => canClosePost && (closePostChoice ?? closePostByDefault);

  /// Above [kPostBudInviteWarningAbove] ticked members the step warns that
  /// each of them gets a request.
  bool get showsManyInvitesWarning =>
      selectedIds.length > kPostBudInviteWarningAbove;

  /// The ticked members, in list order, with their notes.
  List<PostBudInvitee> get invitees => [
    for (final c in invitable)
      if (selectedIds.contains(c.userId))
        PostBudInvitee(
          userId: c.userId,
          note: (notes[c.userId] ?? '').trim().isEmpty
              ? null
              : notes[c.userId]!.trim(),
        ),
  ];

  String nameOf(String userId) => profiles[userId]?.shownName ?? '';
}
