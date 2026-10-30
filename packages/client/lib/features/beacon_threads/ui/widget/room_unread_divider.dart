import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Horizontal divider with an "Unread · N" chip (Telegram-style).
class RoomUnreadDivider extends StatelessWidget {
  const RoomUnreadDivider({required this.unreadCount, super.key});

  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = L10n.of(context)!;
    final chipText = l10n.beaconRoomUnreadDividerCount(unreadCount);
    final compact = context.windowClass == WindowClass.compact;

    final chip = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(TenturaRadii.avatar),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.45),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.tt.screenHPadding,
          vertical: context.tt.iconTextGap,
        ),
        child: Text(
          chipText,
          textAlign: TextAlign.center,
          softWrap: true,
          style: TenturaText.tabLabel(scheme.primary),
        ),
      ),
    );

    final line = Divider(color: scheme.primary.withValues(alpha: 0.35));

    return Semantics(
      label: chipText,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: context.tt.sectionGap),
        child: compact
            ? Column(
                mainAxisSize: MainAxisSize.min,
                spacing: context.tt.tightGap,
                children: [
                  chip,
                  line,
                ],
              )
            : LayoutBuilder(
                builder: (context, constraints) => Row(
                  children: [
                    Expanded(child: line),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: context.tt.screenHPadding,
                      ),
                      child: chip,
                    ),
                    Expanded(child: line),
                  ],
                ),
              ),
      ),
    );
  }
}
