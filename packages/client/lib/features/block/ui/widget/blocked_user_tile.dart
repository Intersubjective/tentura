import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/block/domain/entity/user_block.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// One row for a direct block on the blocked-users list.
class BlockedUserTile extends StatelessWidget {
  const BlockedUserTile({
    required this.intent,
    required this.onUnblock,
    this.onTap,
    super.key,
  });

  final BlockIntent intent;
  final VoidCallback onUnblock;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      leading: TenturaAvatar.medium(profile: intent.blocked),
      title: Text(intent.blocked.shownName),
      subtitle: intent.inheritedCount > 0
          ? Text(
              l10n.blockedHiddenViaInvites(intent.inheritedCount),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      trailing: TenturaTextAction(
        label: l10n.unblockUserMenuItem,
        onPressed: onUnblock,
      ),
    );
  }
}
