import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart'
    show BeaconFactCardStatusBits;
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_pinned_fact_carousel.dart';

/// Current plan, pinned facts, last meaningful change (Phase 4).
class RoomNowStrip extends StatelessWidget {
  const RoomNowStrip({
    required this.roomState,
    required this.factCards,
    this.onOpenFact,
    this.onOpenFileAttachment,
    super.key,
  });

  final BeaconRoomState roomState;
  final List<BeaconFactCard> factCards;

  /// Opens fact actions (room only).
  final Future<void> Function(BeaconFactCard fact)? onOpenFact;

  /// Download/share file attachments (room).
  final Future<void> Function(RoomMessageAttachment attachment)?
      onOpenFileAttachment;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final onV = scheme.onSurfaceVariant;

    final pinnedFacts = factCards
        .where((f) => f.status != BeaconFactCardStatusBits.removed)
        .toList(growable: false)
      ..sort(
        (a, b) {
          final ta = a.updatedAt ?? a.createdAt;
          final tb = b.updatedAt ?? b.createdAt;
          return tb.compareTo(ta);
        },
      );

    final plan = roomState.currentPlan.trim();
    final change = roomState.lastRoomMeaningfulChange?.trim() ?? '';
    final hasBlocker = roomState.openBlockerId != null &&
        roomState.openBlockerId!.isNotEmpty;
    final blockerTitle = roomState.openBlockerTitle?.trim() ?? '';

    if (plan.isEmpty &&
        pinnedFacts.isEmpty &&
        change.isEmpty &&
        !hasBlocker) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: TenturaTechCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                l10n.beaconRoomStripNowTitle,
                style: TenturaText.typeLabel(scheme.onSurface),
              ),
            if (plan.isNotEmpty) ...[
              const SizedBox(height: kSpacingSmall),
              Text(
                l10n.beaconRoomStripPlanLabel,
                style: TenturaText.status(onV),
              ),
              const SizedBox(height: kSpacingSmall / 2),
              SelectableText(
                plan,
                style: TenturaText.body(scheme.onSurface),
              ),
            ],
            if (hasBlocker) ...[
              const SizedBox(height: kSpacingSmall),
              Text(
                blockerTitle.isNotEmpty
                    ? '${l10n.beaconRoomStripOpenBlockerHint} $blockerTitle'
                    : l10n.beaconRoomStripOpenBlockerHint,
                style: TenturaText.status(scheme.tertiary),
              ),
            ],
            if (pinnedFacts.isNotEmpty) ...[
              const SizedBox(height: kSpacingSmall),
              Text(
                l10n.beaconRoomStripLastPrivateFactLabel,
                style: TenturaText.status(onV),
              ),
              const SizedBox(height: kSpacingSmall / 2),
              BeaconPinnedFactCarousel(
                facts: pinnedFacts,
                factTextStyle: TenturaText.body(scheme.onSurface),
                onManageOverflow: onOpenFact,
                onOpenFileAttachment: onOpenFileAttachment,
              ),
            ],
            if (change.isNotEmpty) ...[
              const SizedBox(height: kSpacingSmall),
              Text(
                l10n.beaconRoomStripMeaningfulChangeLabel,
                style: TenturaText.status(onV),
              ),
              const SizedBox(height: kSpacingSmall / 2),
              SelectableText(
                change,
                style: TenturaText.body(scheme.onSurface),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
