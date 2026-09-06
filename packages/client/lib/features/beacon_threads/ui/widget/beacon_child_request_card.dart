import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_hierarchy_summary.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_presenter.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';

BeaconCoordinationPhase _phaseForHierarchyStatus(BeaconStatus status) =>
    switch (status) {
      BeaconStatus.draft => BeaconCoordinationPhase.draft,
      BeaconStatus.reviewOpen => BeaconCoordinationPhase.wrappingUp,
      BeaconStatus.closed => BeaconCoordinationPhase.closed,
      BeaconStatus.cancelled => BeaconCoordinationPhase.cancelled,
      BeaconStatus.deleted => BeaconCoordinationPhase.closed,
      _ => BeaconCoordinationPhase.openFloor,
    };

class BeaconChildRequestCard extends StatelessWidget {
  const BeaconChildRequestCard({
    required this.summary,
    super.key,
  });

  final BeaconHierarchySummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (summary.isTombstone) {
      return Semantics(
        container: true,
        label: l10n.beaconDeletedChild,
        child: BeaconCardShell(
          muted: true,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: tt.tightGap),
            child: Text(
              l10n.beaconDeletedChild,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    final phaseStatus = formatBeaconPhaseStatus(
      l10n,
      BeaconCoordinationPhaseResult(
        phase: _phaseForHierarchyStatus(summary.status),
        suggestedAction: BeaconPhasePrimaryAction.none,
        rowHarmony: BeaconPhaseRowHarmony.empty,
        lifecycleEndedAt: summary.status.isTerminal
            ? summary.publishedAt
            : null,
        slot2Kind: summary.status.isTerminal
            ? BeaconPhaseSlot2Kind.lifecycleEndedAt
            : BeaconPhaseSlot2Kind.none,
      ),
      now: DateTime.now(),
    );

    final owner = summary.owner;
    final title = summary.title?.trim().isNotEmpty == true
        ? summary.title!.trim()
        : l10n.beaconUntitled;

    return BeaconCardShell(
      onTap: () => context.router.push(BeaconViewRoute(id: summary.beaconId)),
      tapSemanticsLabel: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (owner != null)
                TenturaAvatar(
                  profile: Profile(
                    id: owner.id,
                    displayName: owner.displayName,
                    image: owner.avatarImageId != null &&
                            owner.avatarImageId!.isNotEmpty
                        ? ImageEntity(id: owner.avatarImageId!)
                        : null,
                  ),
                  size: tt.avatarSize,
                ),
              if (owner != null) SizedBox(width: tt.avatarTextGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (owner != null) ...[
                      SizedBox(height: tt.tightGap),
                      Text(
                        owner.displayName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: tt.rowGap),
          TenturaStatusLine(
            slot1: phaseStatus.slot1,
            slot2: phaseStatus.slot2,
            slot1Tone: phaseStatus.slot1Tone,
            slot2Tone: phaseStatus.slot2Tone,
          ),
        ],
      ),
    );
  }
}
