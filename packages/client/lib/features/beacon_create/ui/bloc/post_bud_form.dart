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

    @Default(false) bool candidatesLoaded,

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

  /// «Закрыть пост…» is on by default when the Post has at most two members
  /// or every invitable member is ticked.
  bool get closePostByDefault {
    if (memberCount <= 2) return true;
    final eligible = invitable;
    return eligible.isNotEmpty &&
        eligible.every((c) => selectedIds.contains(c.userId));
  }

  bool get closePost => closePostChoice ?? closePostByDefault;

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
