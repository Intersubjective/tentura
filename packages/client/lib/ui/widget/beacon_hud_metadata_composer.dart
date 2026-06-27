import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_hud_derivation.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
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
}) {
  final l10n = L10n.of(context)!;
  final tt = context.tt;
  final entries = <BeaconHudMetadataEntry>[];
  final hideCoordinationHud = beacon.status.isFinished;

  if (BeaconCompactMetadataStrip.hasVisibleContent(
    beacon: beacon,
    involvedProfiles: beacon.helpOfferUsers,
  )) {
    entries.add(
      BeaconHudMetadataEntry(
        icon: BeaconHudRowIcons.people,
        semanticsLabel: l10n.beaconHudPeopleRowSemantics,
        body: BeaconCompactMetadataStrip(
          beacon: beacon,
          involvedProfiles: beacon.helpOfferUsers,
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
    entries.add(
      BeaconHudMetadataEntry(
        icon: BeaconHudRowIcons.now,
        semanticsLabel: l10n.beaconHudNowLabel,
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

    final isHelpOffered = viewModel.role == MyWorkCardRole.helpOffered;
    final isAuthorOrSteward = beacon.author.id == currentUserId;
    final isAwaitingAuthorReview = viewerAwaitingAuthorHelpOfferReview(
      isAuthorOrSteward: isAuthorOrSteward,
      viewerHasActiveHelpOffer: isHelpOffered,
      viewerOfferAuthorResponse: viewModel.authorResponseType,
    );
    final responsibility =
        viewModel.youResponsibility ??
        (isAwaitingAuthorReview ||
                (isAuthorOrSteward && beacon.unansweredHelpOfferCount > 0)
            ? CoordinationResponsibility(beaconId: beacon.id)
            : null);
    if (responsibility != null) {
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
            ),
          ),
        );
      }
    }

    if (myWorkLastEventMetadataVisible(
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
  }

  return entries;
}

List<BeaconHudMetadataEntry> buildBeaconViewHudMetadataEntries(
  BuildContext context, {
  required double rowWidth,
  required BeaconViewState state,
  VoidCallback? onFacePileTap,
  VoidCallback? onEditNowLine,
}) {
  final l10n = L10n.of(context)!;
  final tt = context.tt;
  final entries = <BeaconHudMetadataEntry>[];
  final beacon = state.beacon;
  final viewerId = state.myProfile.id;

  final activeHelpUsers = [
    for (final offer in state.helpOffers)
      if (!offer.isWithdrawn) offer.user,
  ];

  if (BeaconCompactMetadataStrip.hasVisibleContent(
    beacon: beacon,
    involvedProfiles: activeHelpUsers,
  )) {
    entries.add(
      BeaconHudMetadataEntry(
        icon: BeaconHudRowIcons.people,
        semanticsLabel: l10n.beaconHudPeopleRowSemantics,
        body: BeaconCompactMetadataStrip(
          beacon: beacon,
          involvedProfiles: activeHelpUsers,
          currentUserId: viewerId,
          onFacePileTap: onFacePileTap,
        ),
      ),
    );
  }

  final nowDisplay = beaconHudNowDisplay(l10n, state);

  entries.add(
    BeaconHudMetadataEntry(
      icon: BeaconHudRowIcons.now,
      semanticsLabel: l10n.beaconHudNowLabel,
      trailing: onEditNowLine != null
          ? hudNowRowEditButton(
              context: context,
              onEdit: onEditNowLine,
              editSemanticLabel: l10n.beaconHudEditNowLine,
            )
          : null,
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

  final youResponsibility =
      state.youResponsibility ??
      CoordinationResponsibility(beaconId: beacon.id);
  final phaseInput = beaconPhaseInputFromViewState(state);
  final phaseResult = deriveBeaconCoordinationPhase(phaseInput);
  final openBlocker = phaseInput.openBlocker;
  final isAwaitingAuthorReview = viewerAwaitingAuthorHelpOfferReview(
    isAuthorOrSteward: state.isAuthorOrSteward,
    viewerHasActiveHelpOffer: state.isHelpOffered,
    viewerOfferAuthorResponse: state.myActiveHelpOffer?.coordinationResponse,
  );
  final compactSurface = beaconYouCompactSurface(context, rowWidth);
  final authorUnreviewedHelpOfferCount = state.isBeaconMine
      ? state.unansweredHelpOffersCount
      : 0;
  final isViewerBlocked = shouldShowBlockedYouSegment(
    phaseResult: phaseResult,
    openBlocker: openBlocker,
    viewerUserId: viewerId,
    responsibility: youResponsibility,
  );
  final situationInput = buildBeaconYouSituationInput(
    beacon: beacon,
    isAuthorOrSteward: state.isAuthorOrSteward,
    othersOpenCount: youResponsibility.othersOpenCount,
    compactSurface: compactSurface,
    hasRoomObligations: youResponsibility.hasAny,
    authorUnreviewedHelpOfferCount: authorUnreviewedHelpOfferCount,
    viewerBlocked: isViewerBlocked,
    isAwaitingAuthorReview: isAwaitingAuthorReview,
    rowHarmony: phaseResult.rowHarmony,
  );

  if (isBeaconYouRowVisible(input: situationInput)) {
    entries.add(
      BeaconHudMetadataEntry(
        icon: BeaconHudRowIcons.you,
        semanticsLabel: l10n.beaconHudYouLabel,
        body: BeaconYouResponsibilityLine(
          beacon: beacon,
          responsibility: youResponsibility,
          isAuthorOrSteward: state.isAuthorOrSteward,
          tableRowWidth: rowWidth,
          showNewBadges: false,
          viewerUserId: viewerId,
          openBlocker: openBlocker,
          phaseResult: phaseResult,
          isAwaitingAuthorReview: isAwaitingAuthorReview,
          authorUnreviewedHelpOfferCount: authorUnreviewedHelpOfferCount,
        ),
      ),
    );
  }

  return entries;
}

BeaconYouSituationInput buildMyWorkYouSituation({
  required Beacon beacon,
  required MyWorkCardViewModel viewModel,
  required CoordinationResponsibility responsibility,
  required bool isAuthorOrSteward,
  required bool compactSurface,
  required bool isAwaitingAuthorReview,
  required BeaconCoordinationPhaseResult phaseResult,
  required String viewerUserId,
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
  );
}
