import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// OUTCOME: how a finished Request ended (completed, cancelled, deleted).
/// Renders nothing while the Request is still live.
class BeaconHudOutcomeSection extends StatelessWidget {
  const BeaconHudOutcomeSection({
    required this.beacon,
    super.key,
  });

  final Beacon beacon;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final (icon, label, tone) = switch (beacon.status) {
      BeaconStatus.closed => (
        Icons.check_circle_outline,
        l10n.beaconOutcomeClosed,
        TenturaTone.good,
      ),
      BeaconStatus.cancelled => (
        Icons.cancel_outlined,
        l10n.beaconOutcomeCancelled,
        TenturaTone.neutral,
      ),
      BeaconStatus.deleted => (
        Icons.delete_outline,
        l10n.beaconOutcomeDeleted,
        TenturaTone.neutral,
      ),
      _ => (null, null, TenturaTone.neutral),
    };
    if (icon == null || label == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TenturaSectionHeader(label: l10n.beaconOutcomeSection),
        Row(
          children: [
            Icon(icon, size: tt.iconSize, color: tenturaToneColor(tt, tone)),
            SizedBox(width: tt.iconTextGap),
            Expanded(child: TenturaStatusText(label, tone: tone)),
          ],
        ),
        if (beacon.status != BeaconStatus.deleted) ...[
          SizedBox(height: tt.tightGap),
          Text(
            l10n.beaconOutcomeReadOnlyNote,
            style: TenturaText.bodySmall(tt.textMuted),
          ),
        ],
      ],
    );
  }
}

/// ABOUT: the pitch, a few lines of it, and the way into the full Details
/// sheet (needs, dates, place, pictures).
class BeaconHudEssenceSection extends StatelessWidget {
  const BeaconHudEssenceSection({
    required this.beacon,
    required this.onOpenDetails,
    super.key,
  });

  final Beacon beacon;
  final VoidCallback onOpenDetails;

  static const int collapsedLines = 4;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final description = beacon.description.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TenturaSectionHeader(label: l10n.beaconHudEssenceLabel),
        if (description.isNotEmpty)
          Text(
            description,
            maxLines: collapsedLines,
            overflow: TextOverflow.ellipsis,
            style: TenturaText.body(context.tt.text),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TenturaTextAction(
            label: l10n.beaconHudEssenceMore,
            onPressed: onOpenDetails,
            flushStart: true,
            minInteractive: true,
          ),
        ),
      ],
    );
  }
}
