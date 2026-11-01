import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/domain/coordination/helper_offer_response_state.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/ui/util/beacon_hud_now_display.dart';
import 'package:tentura/features/my_work/ui/widget/my_work_last_event_row.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_input_builders.dart';
import 'package:tentura/ui/utils/beacon_you_presentation.dart';
import 'package:tentura/ui/widget/beacon_compact_metadata_strip.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_table.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';
import 'package:tentura/ui/widget/beacon_you_responsibility_line.dart';
import 'package:tentura/ui/widget/hud_labeled_multiline.dart';

List<BeaconHudMetadataEntry> buildMyWorkHudMetadataEntries(
  BuildContext context, {
  required double rowWidth,
  required Beacon beacon,
  required MyWorkCardViewModel viewModel,
  required String currentUserId,
  bool hideLastEventMetadata = false,
  bool hidePeople = false,
  bool hideYou = false,
}) {
  final l10n = L10n.of(context)!;
  final tt = context.tt;
  final entries = <BeaconHudMetadataEntry>[];
  final hideCoordinationHud = beacon.status.isFinished;
  final isHelpOffered = viewModel.role == MyWorkCardRole.helpOffered;
  final isAuthorOrSteward = beacon.author.id == currentUserId;
  final helperOfferState = isHelpOffered
      ? deriveHelperOfferResponseState(
          stakeState: viewModel.stakeState,
          authorResponseType: viewModel.authorResponseType,
          beaconStatus: beacon.status,
        )
      : null;
  final isAwaitingAuthorReview =
      helperOfferState == HelperOfferResponseState.awaitingAuthor;
  final helperHasStandingMessage =
      helperOfferState != null &&
      helperOfferResponseStateHasStandingMessage(helperOfferState);

  if (!hidePeople &&
      BeaconCompactMetadataStrip.hasVisibleContent(
        beacon: beacon,
        involvedProfiles: beacon.admittedHelperUsers,
        helperCount: beacon.admittedHelperCount,
      )) {
    entries.add(
      BeaconHudMetadataEntry(
        icon: BeaconHudRowIcons.people,
        semanticsLabel: l10n.beaconHudPeopleRowSemantics,
        body: BeaconCompactMetadataStrip(
          beacon: beacon,
          involvedProfiles: beacon.admittedHelperUsers,
          helperCount: beacon.admittedHelperCount,
          currentUserId: currentUserId,
        ),
      ),
    );
  }

  if (!hideCoordinationHud) {
    final nowDisplay = myWorkDeskNowDisplay(
      l10n,
      beacon: beacon,
      roomCurrentLine: viewModel.roomCurrentLine,
      openBlockerTitle: viewModel.roomOpenBlockerTitle,
    );
    // #487 — no next step and no blocker: the row would only print the
    // placeholder under an unexplained flag, so it is left out.
    final hasNowContent =
        !nowDisplay.isPlaceholder || nowDisplay.blockerText != null;
    if (hasNowContent) {
      entries.add(
        BeaconHudMetadataEntry(
          icon: BeaconHudRowIcons.now,
          semanticsLabel: l10n.beaconHudNowLabel,
          iconTooltip: l10n.beaconSituationCurrentLineLabel,
          body: HudLabeledMultiline(
            leadingIcon: BeaconHudRowIcons.now,
            semanticsLabel: l10n.beaconHudNowLabel,
            text: nowDisplay.primaryText,
            subline: nowDisplay.blockerText,
            mutedColor: tt.textMuted,
            isPlaceholder: nowDisplay.isPlaceholder,
            includeLead: false,
            primaryMaxLines: 1,
            showTruncationHint: false,
          ),
        ),
      );
    }
  }

  final responsibility =
      viewModel.youResponsibility ??
      (isAwaitingAuthorReview ||
              (isAuthorOrSteward && beacon.unansweredHelpOfferCount > 0) ||
              helperHasStandingMessage
          ? CoordinationResponsibility(beaconId: beacon.id)
          : null);
  if (!hideYou &&
      responsibility != null &&
      (!hideCoordinationHud || helperHasStandingMessage)) {
    final phaseInput = beaconPhaseInputFromMyWorkCard(viewModel);
    final phaseResult = deriveBeaconCoordinationPhase(phaseInput);
    final compactSurface = beaconYouCompactSurface(context, rowWidth);
    final situationInput = buildMyWorkYouSituation(
      beacon: beacon,
      viewModel: viewModel,
      responsibility: responsibility,
      isAuthorOrSteward: isAuthorOrSteward,
      compactSurface: compactSurface,
      isAwaitingAuthorReview: isAwaitingAuthorReview,
      phaseResult: phaseResult,
      viewerUserId: currentUserId,
      helperOfferState: helperOfferState,
    );
    if (isBeaconYouRowVisible(input: situationInput)) {
      entries.add(
        BeaconHudMetadataEntry(
          icon: BeaconHudRowIcons.you,
          semanticsLabel: l10n.beaconHudYouLabel,
          body: BeaconYouResponsibilityLine(
            beacon: beacon,
            responsibility: responsibility,
            isAuthorOrSteward: isAuthorOrSteward,
            tableRowWidth: rowWidth,
            viewerUserId: currentUserId,
            openBlocker: viewModel.roomOpenBlocker,
            phaseResult: phaseResult,
            isAwaitingAuthorReview: isAwaitingAuthorReview,
            authorUnreviewedHelpOfferCount: isAuthorOrSteward
                ? beacon.unansweredHelpOfferCount
                : 0,
            helperOfferState: helperOfferState,
          ),
        ),
      );
    }
  }

  if (!hideLastEventMetadata &&
      !hideCoordinationHud &&
      myWorkLastEventMetadataVisible(
        beacon: beacon,
        viewModel: viewModel,
      )) {
    entries.add(
      BeaconHudMetadataEntry(
        icon: BeaconHudRowIcons.lastEvent,
        semanticsLabel: l10n.beaconHudLastEventRowSemantics,
        body: MyWorkLastEventBody(
          beacon: beacon,
          viewModel: viewModel,
          currentUserId: currentUserId,
        ),
      ),
    );
  }

  return entries;
}

/// Plan rows of the HUD ladder (#220 §5.2): an optional replacement for the
/// YOU row and the rows that follow it (BY PLAN, NEXT).
typedef BeaconHudPlanRows = ({
  BeaconHudMetadataEntry? you,
  List<BeaconHudMetadataEntry> after,
});

/// Builds [BeaconHudPlanRows]; [systemOccupiesYou] is true when a system
/// situation (offers to review, a helper's standing message, …) holds YOU.
typedef BeaconHudPlanRowsBuilder =
    BeaconHudPlanRows Function({required bool systemOccupiesYou});

BeaconYouSituationInput buildMyWorkYouSituation({
  required Beacon beacon,
  required MyWorkCardViewModel viewModel,
  required CoordinationResponsibility responsibility,
  required bool isAuthorOrSteward,
  required bool compactSurface,
  required bool isAwaitingAuthorReview,
  required BeaconCoordinationPhaseResult phaseResult,
  required String viewerUserId,
  HelperOfferResponseState? helperOfferState,
}) {
  final isViewerBlocked = shouldShowBlockedYouSegment(
    phaseResult: phaseResult,
    openBlocker: viewModel.roomOpenBlocker,
    viewerUserId: viewerUserId,
    responsibility: responsibility,
  );
  return buildBeaconYouSituationInput(
    beacon: beacon,
    isAuthorOrSteward: isAuthorOrSteward,
    othersOpenCount: responsibility.othersOpenCount,
    compactSurface: compactSurface,
    hasRoomObligations: responsibility.hasAny,
    authorUnreviewedHelpOfferCount: isAuthorOrSteward
        ? beacon.unansweredHelpOfferCount
        : 0,
    viewerBlocked: isViewerBlocked,
    isAwaitingAuthorReview: isAwaitingAuthorReview,
    rowHarmony: phaseResult.rowHarmony,
    helperOfferState: helperOfferState,
  );
}
