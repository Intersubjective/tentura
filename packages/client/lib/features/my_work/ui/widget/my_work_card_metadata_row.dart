import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_hud_derivation.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_last_event_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_input_builders.dart';
import 'package:tentura/ui/widget/beacon_compact_metadata_strip.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';
import 'package:tentura/ui/widget/beacon_you_responsibility_line.dart';
import 'package:tentura/ui/widget/hud_labeled_multiline.dart';

/// My Work list card metadata: face pile + schedule countdown + location.
class MyWorkCardMetadataRow extends StatelessWidget {
  const MyWorkCardMetadataRow({
    required this.beacon,
    required this.viewModel,
    required this.currentUserId,
    super.key,
  });

  final Beacon beacon;
  final MyWorkCardViewModel viewModel;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final hideCoordinationHud = beacon.lifecycle.isFinished;

    return BeaconHudMetadataColumn(
      children: [
        BeaconCompactMetadataStrip(
          beacon: beacon,
          involvedProfiles: beacon.helpOfferUsers,
          currentUserId: currentUserId,
        ),
        if (!hideCoordinationHud) ...[
          _MyWorkNowRow(
            beacon: beacon,
            viewModel: viewModel,
          ),
          if (viewModel.youResponsibility != null)
            Builder(
              builder: (context) {
                final phaseInput = beaconPhaseInputFromMyWorkCard(viewModel);
                final phaseResult = deriveBeaconCoordinationPhase(phaseInput);
                return BeaconYouResponsibilityLine(
                  beacon: beacon,
                  responsibility: viewModel.youResponsibility!,
                  isAuthorOrSteward: beacon.author.id == currentUserId,
                  viewerUserId: currentUserId,
                  openBlocker: viewModel.roomOpenBlocker,
                  phaseResult: phaseResult,
                );
              },
            ),
          MyWorkLastEventRow(
            beacon: beacon,
            viewModel: viewModel,
            currentUserId: currentUserId,
          ),
        ],
      ],
    );
  }
}

class _MyWorkNowRow extends StatelessWidget {
  const _MyWorkNowRow({
    required this.beacon,
    required this.viewModel,
  });

  final Beacon beacon;
  final MyWorkCardViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final nowDisplay = myWorkDeskNowDisplay(
      l10n,
      beacon: beacon,
      roomCurrentLine: viewModel.roomCurrentLine,
      openBlockerTitle: viewModel.roomOpenBlockerTitle,
    );

    return HudLabeledMultiline(
      leadingIcon: BeaconHudRowIcons.now,
      semanticsLabel: l10n.beaconHudNowLabel,
      text: nowDisplay.primaryText,
      subline: nowDisplay.blockerText,
      mutedColor: tt.textMuted,
      isPlaceholder: nowDisplay.isPlaceholder,
    );
  }
}
