import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Current viewer role + next move + quick actions (Phase 4; Mark done in Phase 5).
class BeaconRoomYouStrip extends StatelessWidget {
  const BeaconRoomYouStrip({
    required this.myParticipant,
    required this.onEditNextMove,
    required this.collapsed,
    required this.onToggleCollapse,
    super.key,
  });

  final BeaconParticipant? myParticipant;
  final VoidCallback onEditNextMove;
  final bool collapsed;
  final VoidCallback onToggleCollapse;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final onV = scheme.onSurfaceVariant;
    final me = myParticipant;

    if (me == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Text(
          l10n.beaconRoomYouStripNoParticipant,
          style: TenturaText.bodySmall(onV),
        ),
      );
    }

    final roleLabel = _roleL10n(l10n, me.role);
    final next = me.nextMoveText?.trim();

    Widget titleRow(TextStyle titleStyle, {required bool trailingChevronDown}) =>
        Row(
          children: [
            Expanded(
              child: Text(l10n.beaconRoomYouStripTitle, style: titleStyle),
            ),
            Tooltip(
              message: collapsed
                  ? l10n.beaconRoomYouExpandTooltip
                  : l10n.beaconRoomYouCollapseTooltip,
              child: IconButton(
                onPressed: onToggleCollapse,
                iconSize: 22,
                visualDensity: VisualDensity.compact,
                tooltip: collapsed
                    ? l10n.beaconRoomYouExpandTooltip
                    : l10n.beaconRoomYouCollapseTooltip,
                icon: Icon(
                  trailingChevronDown
                      ? Icons.expand_more_rounded
                      : Icons.expand_less_rounded,
                ),
              ),
            ),
          ],
        );

    if (collapsed) {
      final summary = (next != null && next.isNotEmpty)
          ? next.split('\n').first.trim().isEmpty
              ? roleLabel
              : next.split('\n').first.trim()
          : roleLabel;
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: TenturaTechCard(
          padding: EdgeInsets.zero,
          child: InkWell(
            onTap: onToggleCollapse,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.person_outline_rounded, color: scheme.primary),
                  const SizedBox(width: kSpacingSmall),
                  Expanded(
                    child: Text(
                      '${l10n.beaconRoomYouStripTitle}: $summary',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TenturaText.body(scheme.onSurface),
                    ),
                  ),
                  Tooltip(
                    message: l10n.beaconRoomYouExpandTooltip,
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: onV,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TenturaTechCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onToggleCollapse,
              child: titleRow(
                TenturaText.typeLabel(scheme.onSurface),
                trailingChevronDown: false,
              ),
            ),
            const SizedBox(height: kSpacingSmall),
            Text(
              l10n.beaconRoomYouStripRoleLabel,
              style: TenturaText.status(onV),
            ),
            const SizedBox(height: kSpacingSmall / 2),
            Text(roleLabel, style: TenturaText.body(scheme.onSurface)),
            const SizedBox(height: kSpacingSmall),
            Text(
              l10n.beaconRoomYouStripNextMoveLabel,
              style: TenturaText.status(onV),
            ),
            const SizedBox(height: kSpacingSmall / 2),
            Text(
              next != null && next.isNotEmpty ? next : '—',
              style: TenturaText.body(scheme.onSurface),
            ),
            const SizedBox(height: kSpacingSmall),
            Wrap(
              spacing: kSpacingSmall,
              runSpacing: kSpacingSmall / 2,
              children: [
                TextButton(
                  onPressed: onEditNextMove,
                  child: Text(l10n.beaconRoomYouStripEditNextMove),
                ),
                TextButton(
                  onPressed: null,
                  child: Text(l10n.beaconRoomYouStripMarkDoneComing),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _roleL10n(L10n l10n, int role) {
    return switch (role) {
      BeaconParticipantRoleBits.author => l10n.beaconPeopleRoleAuthor,
      BeaconParticipantRoleBits.steward => l10n.beaconPeopleRoleSteward,
      BeaconParticipantRoleBits.helper => l10n.beaconPeopleRoleHelper,
      BeaconParticipantRoleBits.candidate => l10n.beaconPeopleRoleCandidate,
      BeaconParticipantRoleBits.watcher => l10n.beaconPeopleRoleWatcher,
      BeaconParticipantRoleBits.forwarder => l10n.beaconPeopleRoleForwarder,
      _ => l10n.beaconPeopleStatusUnknown(role),
    };
  }
}
