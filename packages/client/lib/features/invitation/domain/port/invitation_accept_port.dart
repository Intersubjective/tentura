import '../entity/invite_preview.dart';

enum ExistingInviteAcceptance { accepted, requestLapsed }

/// Invite preview + accept-as-existing for authenticated users.
abstract class InvitationAcceptPort {
  Future<InvitePreview> fetchInvitePreview(String code);

  Future<ExistingInviteAcceptance> acceptExistingInvite(String code);
}
