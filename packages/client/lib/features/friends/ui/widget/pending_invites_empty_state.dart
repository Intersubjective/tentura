import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Empty state for the Pending invitations list.
///
/// Stands on its own: no share link is on screen here, so it must not use
/// the share-dialog caption about "this link".
class PendingInvitesEmptyState extends StatelessWidget {
  const PendingInvitesEmptyState({
    required this.onCreateInvitation,
    super.key,
  });

  final VoidCallback onCreateInvitation;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final onSurfaceVariant = theme.colorScheme.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.person_add_alt_1_outlined,
          size: tt.iconSize * 3,
          color: onSurfaceVariant,
        ),
        SizedBox(height: tt.sectionGap),
        Text(
          l10n.friendsInvitesPendingEmptyTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            color: onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: tt.rowGap),
        Text(
          l10n.friendsInvitesPendingEmptyBody,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: tt.sectionGap),
        FilledButton.icon(
          icon: const Icon(Icons.person_add_alt_1),
          label: Text(l10n.friendsCreateInvitation),
          onPressed: onCreateInvitation,
        ),
      ],
    );
  }
}
