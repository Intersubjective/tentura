import 'package:flutter/material.dart';

import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_input_builders.dart';
import 'package:tentura/ui/presenter/beacon_phase_presenter.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/beacon_requirements_bar.dart';

/// Profile-beacon list tile — uses [Beacon] directly (no synthetic [InboxItem]).
class BeaconTile extends StatelessWidget {
  const BeaconTile({
    required this.beacon,
    required this.onOpenBeacon,
    required this.onForward,
    super.key,
  });

  final Beacon beacon;
  final VoidCallback onOpenBeacon;
  final VoidCallback onForward;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;

    final phaseInput = beaconPhaseInputFromInbox(beacon: beacon);
    final phaseResult = deriveBeaconCoordinationPhase(phaseInput);
    final phaseStatus = formatBeaconPhaseStatus(
      l10n,
      phaseResult,
      now: DateTime.now(),
    );
    final updatedLine = beaconHasRealUpdate(beacon)
        ? l10n.myWorkUpdatedLine(
            '${dateFormatYMD(beacon.updatedAt)} ${timeFormatHm(beacon.updatedAt)}',
          )
        : null;

    return BeaconCardShell(
      onTap: onOpenBeacon,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BeaconCardHeaderRow(
            beacon: beacon,
            statusLine: phaseStatus.statusLine,
            statusTone: phaseStatus.tone,
            menu: BeaconOverflowMenu(
              beacon: beacon,
              onOpenBeacon: onOpenBeacon,
              onForward: onForward,
              onForwardsGraph: () =>
                  context.read<ScreenCubit>().showForwardsGraphFor(beacon.id),
            ),
          ),
          SizedBox(height: tt.rowGap),
          BeaconCardMetadataLine(
            beacon: beacon,
            updatedLine: updatedLine,
          ),
          if (beacon.needs.isNotEmpty) ...[
            SizedBox(height: tt.rowGap),
            BeaconRequirementsBar(needs: beacon.needs),
          ],
        ],
      ),
    );
  }
}
