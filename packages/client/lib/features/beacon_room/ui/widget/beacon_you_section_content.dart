import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Expanded YOU body (role, next move / accepted ask, quick actions).
class BeaconYouSectionContent extends StatelessWidget {
  const BeaconYouSectionContent({
    required this.myParticipant,
    required this.onEditNextMove,
    required this.onAddMyNextMove,
    this.viewerAcceptedAsk,
    super.key,
  });

  final BeaconParticipant? myParticipant;
  final CoordinationItem? viewerAcceptedAsk;
  final VoidCallback onEditNextMove;
  final VoidCallback onAddMyNextMove;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final onV = scheme.onSurfaceVariant;
    final me = myParticipant;

    if (me == null) {
      return Text(
        l10n.beaconRoomYouStripNoParticipant,
        style: TenturaText.bodySmall(onV),
      );
    }

    final roleLabel = _roleL10n(l10n, me.role);
    final askCommitment = viewerAcceptedAsk?.title.trim();
    final next = (askCommitment != null && askCommitment.isNotEmpty)
        ? askCommitment
        : me.nextMoveText?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.beaconRoomYouStripRoleLabel,
          style: TenturaText.status(onV),
        ),
        const SizedBox(height: kSpacingSmall / 2),
        Text(roleLabel, style: TenturaText.body(scheme.onSurface)),
        const SizedBox(height: kSpacingSmall),
        Text(
          viewerAcceptedAsk != null &&
                  viewerAcceptedAsk!.title.trim().isNotEmpty
              ? l10n.beaconRoomYouStripAcceptedAskLabel
              : l10n.beaconRoomYouStripNextMoveLabel,
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
            Semantics(
              button: true,
              label: l10n.beaconRoomAddMyNextMove,
              child: TextButton(
                onPressed: onAddMyNextMove,
                child: Text(l10n.beaconRoomAddMyNextMove),
              ),
            ),
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
