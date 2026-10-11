import 'package:tentura/domain/entity/author_invite.dart';

/// The author-invite lifecycle and its read projections (plan C4/C6).
abstract interface class AuthorInvitePort {
  /// A later invite by the Request author.
  Future<AuthorInviteCreateResult> create({
    required String beaconId,
    required String userId,
    String? note,
  });

  Future<AuthorInvite> accept({required String inviteId});

  Future<AuthorInvite> decline({required String inviteId});

  Future<AuthorInvite> withdraw({required String inviteId});

  /// The caller's pending invites (the «Для вас» invite card).
  Future<List<PendingAuthorInvite>> myPending();

  /// Invites on the caller's Request (the child People tab).
  Future<List<AuthorInvite>> beaconInvites({required String beaconId});
}
