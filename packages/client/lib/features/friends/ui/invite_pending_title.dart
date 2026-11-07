import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Row title for a pending people invite: private addressee label, else a
/// readable default (not the raw invite id — #1078).
String pendingPeopleInviteTitle(L10n l10n, InvitationEntity invitation) {
  final addressee = invitation.addresseeName?.trim();
  if (addressee != null && addressee.isNotEmpty) {
    return addressee;
  }
  return l10n.friendsInvitePendingUntitled;
}
