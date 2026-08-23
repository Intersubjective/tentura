import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../invite_accepted_subtitle.dart';

/// A consumed-invite row: who accepted, when, and (via [onTap]) a way to
/// navigate to them or the Request it was tied to. No edit/delete actions —
/// nothing left to rename or cancel once an invite is consumed. Copy
/// distinguishes a brand-new signup from an existing user becoming a friend
/// via [InvitationEntity.inviteOrigin].
class AcceptedInviteListTile extends StatelessWidget {
  const AcceptedInviteListTile({
    required this.invitation,
    required this.l10n,
    this.onTap,
    super.key,
  });

  final InvitationEntity invitation;
  final L10n l10n;

  /// Null when there's nothing to navigate to (e.g. the accepter is hidden
  /// to this viewer) — the row renders as a plain, non-interactive record.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final profile = Profile(
      id: invitation.invitedId ?? '',
      contactName: invitation.addresseeName ?? '',
      displayName: invitation.invitedName ?? '',
      image: (invitation.invitedImageId?.isNotEmpty ?? false)
          ? ImageEntity(id: invitation.invitedImageId!)
          : null,
    );
    final displayName = profile.displayLabel(l10n.noName);
    final originLine = switch (invitation.inviteOrigin) {
      'existing_account' => l10n.friendsInviteAcceptedExistingAccount(
        displayName,
      ),
      // Defensive default; the DB CHECK constraint guarantees this is
      // non-null for any accepted row.
      _ => l10n.friendsInviteAcceptedNewAccount(displayName),
    };
    final subtitle = inviteAcceptedSubtitle(
      l10n: l10n,
      acceptedAt: invitation.acceptedAt ?? invitation.createdAt,
      now: DateTime.now(),
    );

    return ListTile(
      contentPadding: EdgeInsets.symmetric(
        horizontal: tt.screenHPadding,
        vertical: tt.sectionGap,
      ),
      leading: TenturaAvatar.small(profile: profile),
      title: Text(originLine),
      subtitle: Text(subtitle),
      enabled: onTap != null,
      onTap: onTap,
    );
  }
}
