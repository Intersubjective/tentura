import 'package:freezed_annotation/freezed_annotation.dart';

import 'post_bud_invite_outcome.dart';

part 'author_invite.freezed.dart';

/// `beacon_author_invite.status` by name (plan C4).
enum AuthorInviteStatus {
  pending,
  accepted,
  declined,
  withdrawn,
  expired,
  superseded;

  static AuthorInviteStatus fromWire(String raw) =>
      values.firstWhere((s) => s.name == raw, orElse: () => expired);

  bool get isPending => this == pending;
}

/// An author invite on a Request (plan C4/C6).
///
/// The author's list (`beaconAuthorInvites`) fills [inviteeId], [note] and
/// [createdAt]; an accept/decline/withdraw result carries only [id],
/// [beaconId] and [status].
@freezed
abstract class AuthorInvite with _$AuthorInvite {
  const factory AuthorInvite({
    required String id,
    required String beaconId,
    required AuthorInviteStatus status,
    String? inviteeId,
    String? note,
    DateTime? createdAt,
  }) = _AuthorInvite;
}

/// A pending invite as its invitee sees it (`myPendingAuthorInvites`, the
/// «Для вас» invite card).
@freezed
abstract class PendingAuthorInvite with _$PendingAuthorInvite {
  const factory PendingAuthorInvite({
    required String id,
    required String beaconId,
    required String beaconTitle,
    required String inviterId,
    required DateTime createdAt,
    String? sourcePostId,
    String? note,
  }) = _PendingAuthorInvite;
}

/// `beaconAuthorInviteCreate`: the outcome and, when invited, the invite id.
@freezed
abstract class AuthorInviteCreateResult with _$AuthorInviteCreateResult {
  const factory AuthorInviteCreateResult({
    required PostBudInviteOutcome outcome,
    String? inviteId,
  }) = _AuthorInviteCreateResult;
}
