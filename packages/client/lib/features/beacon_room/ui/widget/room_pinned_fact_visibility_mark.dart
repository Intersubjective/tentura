import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Compact pinned-fact visibility ribbon (public vs chat-only).
class RoomPinnedFactVisibilityMark extends StatelessWidget {
  const RoomPinnedFactVisibilityMark({
    required this.visibility,
    this.compact = false,
    super.key,
  });

  final int visibility;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final isPublic = visibility == BeaconFactCardVisibilityBits.public;
    final label = compact
        ? (isPublic
            ? l10n.beaconRoomFactCardVisibilityPublic
            : l10n.beaconRoomFactCardVisibilityChat)
        : (isPublic
            ? l10n.beaconRoomMessagePinnedFactChipPublic
            : l10n.beaconRoomMessagePinnedFactChipPrivate);
    final iconColor = isPublic ? tt.info : tt.textMuted;
    final icon = isPublic ? Icons.public_outlined : Icons.push_pin_outlined;

    return Semantics(
      label: label,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: tt.iconSize * 0.75, color: iconColor),
          SizedBox(width: tt.iconTextGap / 2),
          Flexible(
            child: TenturaStatusText(
              label,
              tone: isPublic ? TenturaTone.info : TenturaTone.neutral,
            ),
          ),
        ],
      ),
    );
  }
}

bool roomPinnedFactIsVisible(BeaconFactCard fact) =>
    fact.status == BeaconFactCardStatusBits.active ||
    fact.status == BeaconFactCardStatusBits.corrected;
