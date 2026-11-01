import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/coordination/derive_beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/presenter/beacon_hud_author_action.dart';
import 'package:tentura/features/beacon_view/ui/presenter/beacon_phase_input_from_view_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_hud_derivation.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/beacon_you_presentation.dart';
import 'package:tentura/ui/widget/beacon_hud_metadata_table.dart';
import 'package:tentura/ui/widget/beacon_hud_row_lead.dart';
import 'package:tentura/ui/widget/beacon_you_responsibility_line.dart';
import 'package:tentura/ui/widget/hud_labeled_multiline.dart';

typedef BeaconHudPlanRowsBuilder =
    ({
      BeaconHudMetadataEntry? you,
      List<BeaconHudMetadataEntry> after,
    })
    Function({required bool systemOccupiesYou});

List<BeaconHudMetadataEntry> buildBeaconViewHudMetadataEntries(
  BuildContext context, {
  required double rowWidth,
  required BeaconViewState state,
  VoidCallback? onEditNowLine,
  VoidCallback? onReviewAuthorOffers,
  BeaconHudPlanRowsBuilder? planRows,
  bool includeNow = true,
}) {
  final l10n = L10n.of(context)!;
  final tt = context.tt;
  final entries = <BeaconHudMetadataEntry>[];
  final beacon = state.beacon;
  final viewerId = state.myProfile.id;

  if (beacon.status == BeaconStatus.closed) return entries;

  final nowDisplay = beaconHudNowDisplay(l10n, state);

  if (includeNow) {
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
  }

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

  final plan = planRows?.call(
    systemOccupiesYou: hasBeaconYouPersonalObligation(input: situationInput),
  );
  final planYou = plan?.you;
  if (planYou != null) {
    entries.add(planYou);
  } else if (isBeaconYouRowVisible(input: situationInput)) {
    final hasAuthorReviewObligation =
        state.isAuthorOrSteward && authorUnreviewedHelpOfferCount > 0;
    final authorForwardCue =
        state.isBeaconMine &&
        beacon.viewerCanForward &&
        deriveBeaconHudAuthorAction(state) == null &&
        deriveBeaconYouEmptyFallback(input: situationInput) ==
            BeaconYouEmptyFallback.noOpenItems;
    entries.add(
      BeaconHudMetadataEntry(
        icon: BeaconHudRowIcons.you,
        semanticsLabel: l10n.beaconHudYouLabel,
        onTap: hasAuthorReviewObligation ? onReviewAuthorOffers : null,
        semanticsValue: hasAuthorReviewObligation
            ? l10n.beaconHudYouAuthorReview(authorUnreviewedHelpOfferCount)
            : null,
        body: authorForwardCue
            ? TenturaStatusText(
                beaconHudYouLine(l10n, state),
                maxLines: null,
                overflow: TextOverflow.visible,
              )
            : BeaconYouResponsibilityLine(
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
  if (plan != null) entries.addAll(plan.after);

  return entries;
}
