import '../entity/invite_preview.dart';

/// Invite preview + accept-as-existing for authenticated users.
abstract class InvitationAcceptPort {
  Future<InvitePreview> fetchInvitePreview(String code);

  Future<void> acceptExistingInvite(String code);
}
