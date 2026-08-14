import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Horizontal divider with an "Unread · N" chip (Telegram-style).
class RoomUnreadDivider extends StatelessWidget {
  const RoomUnreadDivider({required this.unreadCount, super.key});

  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = L10n.of(context)!;
    final chipText = l10n.beaconRoomUnreadDividerCount(unreadCount);

    return Semantics(
      label: chipText,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(child: Divider(color: scheme.primary.withValues(alpha: 0.35))),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kSpacingMedium),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.45),
                  ),
                ),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: kSpacingMedium, vertical: 6),
                  child: Text(
                    chipText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TenturaText.tabLabel(scheme.primary),
                  ),
                ),
              ),
            ),
            Expanded(child: Divider(color: scheme.primary.withValues(alpha: 0.35))),
          ],
        ),
      ),
    );
  }
}
