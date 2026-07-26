import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/coordination/beacon_you_situation.dart'
    as you_situation;
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/open_blocker_cue.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_input_builders.dart';
import 'package:tentura/ui/widget/coordination_item_presenter.dart';

typedef BeaconYouEmptyFallback = you_situation.BeaconYouEmptyFallback;
typedef BeaconYouOfferReviewSegmentKind =
    you_situation.BeaconYouOfferReviewSegmentKind;
typedef BeaconYouSituationInput = you_situation.BeaconYouSituationInput;

bool viewerAwaitingAuthorHelpOfferReview({
  required bool isAuthorOrSteward,
  required CoordinationResponseType? viewerOfferAuthorResponse,
  required bool viewerHasActiveHelpOffer,
}) => you_situation.viewerAwaitingAuthorHelpOfferReview(
  isAuthorOrSteward: isAuthorOrSteward,
  viewerOfferAuthorResponse: viewerOfferAuthorResponse,
  viewerHasActiveHelpOffer: viewerHasActiveHelpOffer,
);

BeaconYouEmptyFallback deriveBeaconYouEmptyFallback({
  required BeaconYouSituationInput input,
}) => you_situation.deriveBeaconYouEmptyFallback(input);

bool hasBeaconYouPersonalObligation({
  required BeaconYouSituationInput input,
}) => you_situation.hasBeaconYouPersonalObligation(input);

bool isBeaconYouRowVisible({
  required BeaconYouSituationInput input,
}) => you_situation.isBeaconYouRowVisible(input);

List<BeaconYouOfferReviewSegmentKind> offerReviewSegments({
  required BeaconYouSituationInput input,
}) => you_situation.offerReviewSegments(input);

BeaconYouSituationInput buildBeaconYouSituationInput({
  required Beacon beacon,
  required bool isAuthorOrSteward,
  required int othersOpenCount,
  required bool compactSurface,
  required bool hasRoomObligations,
  required int authorUnreviewedHelpOfferCount,
  required bool viewerBlocked,
  bool isAwaitingAuthorReview = false,
  BeaconPhaseRowHarmony rowHarmony = BeaconPhaseRowHarmony.empty,
}) {
  return BeaconYouSituationInput(
    lifecycle: beacon.status,
    isAuthorOrSteward: isAuthorOrSteward,
    othersOpenCount: othersOpenCount,
    compactSurface: compactSurface,
    hasRoomObligations: hasRoomObligations,
    isAwaitingAuthorReview: isAwaitingAuthorReview,
    authorUnreviewedHelpOfferCount: authorUnreviewedHelpOfferCount,
    rowHarmony: rowHarmony,
    viewerBlocked: viewerBlocked,
  );
}

bool shouldShowBlockedYouSegment({
  required BeaconCoordinationPhaseResult? phaseResult,
  required OpenBlockerCue? openBlocker,
  required String viewerUserId,
  required CoordinationResponsibility? responsibility,
}) {
  if (phaseResult?.rowHarmony.preferBlockedYouSegment != true) {
    return false;
  }
  return blockerOpenTargetsViewer(
    responsibility: responsibility,
    openBlocker: openBlocker,
    viewerUserId: viewerUserId,
  );
}

@immutable
class BeaconYouBlockedSegmentPresentation {
  const BeaconYouBlockedSegmentPresentation({
    required this.label,
    required this.semanticsLabel,
    this.raiserAvatar,
    this.elapsedLabel,
    this.labelTone = TenturaTone.warn,
    this.elapsedTone = TenturaTone.neutral,
  });

  final String label;
  final String semanticsLabel;
  final Widget? raiserAvatar;
  final String? elapsedLabel;
  final TenturaTone labelTone;
  final TenturaTone elapsedTone;
}

@immutable
class BeaconYouSegmentPresentation {
  const BeaconYouSegmentPresentation({
    required this.icon,
    required this.count,
    this.label,
    this.newCount = 0,
    this.tone,
  });

  final IconData icon;
  final int count;
  final String? label;

  /// When null, renders as content ([ColorScheme.onSurface]).
  final TenturaTone? tone;
  final int newCount;
}

@immutable
class BeaconYouPresentation {
  const BeaconYouPresentation.segments({
    required this.segments,
    this.blockedSegment,
  }) : fallbackText = null,
       fallbackTone = TenturaTone.neutral,
       blockedOnly = false;

  const BeaconYouPresentation.blockedOnly({
    required this.blockedSegment,
  }) : segments = const [],
       fallbackText = null,
       fallbackTone = TenturaTone.neutral,
       blockedOnly = true;

  const BeaconYouPresentation.fallback({
    required this.fallbackText,
    this.fallbackTone = TenturaTone.neutral,
  }) : segments = const [],
       blockedSegment = null,
       blockedOnly = false;

  const BeaconYouPresentation.hidden()
    : segments = const [],
      fallbackText = null,
      fallbackTone = TenturaTone.neutral,
      blockedSegment = null,
      blockedOnly = false;

  final List<BeaconYouSegmentPresentation> segments;
  final BeaconYouBlockedSegmentPresentation? blockedSegment;
  final String? fallbackText;
  final TenturaTone fallbackTone;
  final bool blockedOnly;

  bool get isHidden =>
      segments.isEmpty &&
      blockedSegment == null &&
      (fallbackText == null || fallbackText!.isEmpty);
}

BeaconYouPresentation buildBeaconYouPresentation(
  L10n l10n,
  CoordinationResponsibility responsibility, {
  required bool collapse,
  required BeaconYouSituationInput situationInput,
  required BeaconYouEmptyFallback emptyFallback,
  required bool showNewBadges,
  BeaconYouBlockedSegmentPresentation? blockedSegment,
  BeaconCoordinationPhaseResult? phaseResult,
}) {
  final reviewSegments = offerReviewSegments(input: situationInput);
  if (blockedSegment != null &&
      !responsibility.hasAny &&
      reviewSegments.isEmpty) {
    return BeaconYouPresentation.blockedOnly(blockedSegment: blockedSegment);
  }

  if (responsibility.hasAny) {
    final segments = <BeaconYouSegmentPresentation>[
      ..._buildOfferReviewSegmentPresentations(
        l10n,
        reviewSegments,
        situationInput: situationInput,
        collapse: collapse,
      ),
      ...responsibility.orderedEntries.map(
        (entry) => BeaconYouSegmentPresentation(
          icon: coordinationKindIcon(entry.kind),
          count: entry.open,
          label: collapse ? null : _kindLabel(l10n, entry.kind, entry.open),
          newCount: showNewBadges ? entry.newCount : 0,
          tone: toneForCoordinationKind(entry.kind),
        ),
      ),
    ];
    return BeaconYouPresentation.segments(
      segments: segments,
      blockedSegment: blockedSegment,
    );
  }

  return switch (emptyFallback) {
    BeaconYouEmptyFallback.hidden => const BeaconYouPresentation.hidden(),
    BeaconYouEmptyFallback.waitingOnOthers => BeaconYouPresentation.fallback(
      fallbackText: l10n.beaconYouWaitingOnOthers,
      fallbackTone: toneForYouEmptyFallback(
        emptyFallback,
        phase: phaseResult?.phase,
      ),
    ),
    BeaconYouEmptyFallback.noOpenItems => BeaconYouPresentation.fallback(
      fallbackText: l10n.beaconYouNoOpenItems,
      fallbackTone: toneForYouEmptyFallback(
        emptyFallback,
        phase: phaseResult?.phase,
      ),
    ),
    BeaconYouEmptyFallback.awaitingAuthorReview =>
      BeaconYouPresentation.fallback(
        fallbackText: l10n.beaconYouOfferSent,
        fallbackTone: toneForYouEmptyFallback(
          emptyFallback,
          phase: phaseResult?.phase,
        ),
      ),
    BeaconYouEmptyFallback.authorReviewOffers => BeaconYouPresentation.fallback(
      fallbackText: l10n.beaconHudYouAuthorReview(
        situationInput.authorUnreviewedHelpOfferCount,
      ),
      fallbackTone: toneForYouEmptyFallback(
        emptyFallback,
        phase: phaseResult?.phase,
      ),
    ),
    BeaconYouEmptyFallback.noInfo => BeaconYouPresentation.fallback(
      fallbackText: l10n.beaconYouNoInfo,
      fallbackTone: toneForYouEmptyFallback(
        emptyFallback,
        phase: phaseResult?.phase,
      ),
    ),
    BeaconYouEmptyFallback.closed => BeaconYouPresentation.fallback(
      fallbackText: l10n.beaconYouClosed,
      fallbackTone: toneForYouEmptyFallback(
        emptyFallback,
        phase: phaseResult?.phase,
      ),
    ),
  };
}

List<BeaconYouSegmentPresentation> _buildOfferReviewSegmentPresentations(
  L10n l10n,
  List<BeaconYouOfferReviewSegmentKind> segments, {
  required BeaconYouSituationInput situationInput,
  required bool collapse,
}) {
  return [
    for (final segment in segments)
      switch (segment) {
        BeaconYouOfferReviewSegmentKind.authorReview =>
          BeaconYouSegmentPresentation(
            icon: coordinationKindIcon(CoordinationItemKind.resolution),
            count: situationInput.authorUnreviewedHelpOfferCount,
            label: collapse
                ? null
                : l10n.beaconHudYouAuthorReview(
                    situationInput.authorUnreviewedHelpOfferCount,
                  ),
            tone: toneForOfferReviewSegment(segment),
          ),
        BeaconYouOfferReviewSegmentKind.helperAwaitingAuthor =>
          BeaconYouSegmentPresentation(
            icon: coordinationKindIcon(CoordinationItemKind.resolution),
            count: 0,
            label: l10n.beaconYouOfferSent,
            tone: toneForOfferReviewSegment(segment),
          ),
      },
  ];
}

TenturaTone toneForYouEmptyFallback(
  BeaconYouEmptyFallback fallback, {
  BeaconCoordinationPhase? phase,
}) {
  return switch (fallback) {
    BeaconYouEmptyFallback.authorReviewOffers => TenturaTone.info,
    BeaconYouEmptyFallback.awaitingAuthorReview => TenturaTone.info,
    BeaconYouEmptyFallback.waitingOnOthers => TenturaTone.neutral,
    BeaconYouEmptyFallback.noInfo => TenturaTone.neutral,
    BeaconYouEmptyFallback.closed => TenturaTone.neutral,
    BeaconYouEmptyFallback.noOpenItems => _noOpenItemsTone(phase),
    BeaconYouEmptyFallback.hidden => TenturaTone.neutral,
  };
}

TenturaTone _noOpenItemsTone(BeaconCoordinationPhase? phase) {
  if (phase == null) return TenturaTone.neutral;
  return switch (phase) {
    BeaconCoordinationPhase.blocked => TenturaTone.neutral,
    BeaconCoordinationPhase.needsMoreHelp => TenturaTone.neutral,
    BeaconCoordinationPhase.closed => TenturaTone.neutral,
    BeaconCoordinationPhase.cancelled => TenturaTone.neutral,
    BeaconCoordinationPhase.draft => TenturaTone.neutral,
    _ => TenturaTone.good,
  };
}

TenturaTone? toneForCoordinationKind(CoordinationItemKind kind) =>
    switch (kind) {
      CoordinationItemKind.ask => null,
      CoordinationItemKind.promise => null,
      CoordinationItemKind.blocker => TenturaTone.warn,
      CoordinationItemKind.resolution => TenturaTone.info,
      CoordinationItemKind.plan => TenturaTone.neutral,
    };

TenturaTone toneForOfferReviewSegment(
  BeaconYouOfferReviewSegmentKind kind,
) => switch (kind) {
      BeaconYouOfferReviewSegmentKind.authorReview => TenturaTone.info,
      BeaconYouOfferReviewSegmentKind.helperAwaitingAuthor => TenturaTone.info,
    };

String _kindLabel(L10n l10n, CoordinationItemKind kind, int count) =>
    switch (kind) {
      CoordinationItemKind.ask => l10n.beaconYouAskCount(count),
      CoordinationItemKind.promise => l10n.beaconYouPromiseCount(count),
      CoordinationItemKind.blocker => l10n.beaconYouBlockerCount(count),
      CoordinationItemKind.resolution => l10n.beaconYouReviewCount(count),
      CoordinationItemKind.plan => '',
    };

BeaconYouEmptyFallback deriveBeaconYouEmptyFallbackFromBeacon({
  required Beacon beacon,
  required CoordinationResponsibility responsibility,
  required bool isAuthorOrSteward,
  required bool compactSurface,
  required String viewerUserId,
  required int authorUnreviewedHelpOfferCount,
  BeaconCoordinationPhaseResult? phaseResult,
  OpenBlockerCue? openBlocker,
  bool isAwaitingAuthorReview = false,
}) {
  final blocked = shouldShowBlockedYouSegment(
    phaseResult: phaseResult,
    openBlocker: openBlocker,
    viewerUserId: viewerUserId,
    responsibility: responsibility,
  );
  final input = buildBeaconYouSituationInput(
    beacon: beacon,
    isAuthorOrSteward: isAuthorOrSteward,
    othersOpenCount: responsibility.othersOpenCount,
    compactSurface: compactSurface,
    hasRoomObligations: responsibility.hasAny,
    authorUnreviewedHelpOfferCount: authorUnreviewedHelpOfferCount,
    viewerBlocked: blocked,
    isAwaitingAuthorReview: isAwaitingAuthorReview,
    rowHarmony: phaseResult?.rowHarmony ?? BeaconPhaseRowHarmony.empty,
  );
  return deriveBeaconYouEmptyFallback(
    input: input,
  );
}

/// Whether the YOU metadata table row should be emitted (vs omitted entirely).
bool isBeaconYouMetadataVisible({
  required Beacon beacon,
  required CoordinationResponsibility responsibility,
  required bool isAuthorOrSteward,
  required bool compactSurface,
  required int authorUnreviewedHelpOfferCount,
  required bool isAwaitingAuthorReview,
  BeaconCoordinationPhaseResult? phaseResult,
  OpenBlockerCue? openBlocker,
  String viewerUserId = '',
}) {
  final blocked = shouldShowBlockedYouSegment(
    phaseResult: phaseResult,
    openBlocker: openBlocker,
    viewerUserId: viewerUserId,
    responsibility: responsibility,
  );
  if (responsibility.hasAny || blocked) {
    return true;
  }
  final input = buildBeaconYouSituationInput(
    beacon: beacon,
    isAuthorOrSteward: isAuthorOrSteward,
    othersOpenCount: responsibility.othersOpenCount,
    compactSurface: compactSurface,
    hasRoomObligations: responsibility.hasAny,
    authorUnreviewedHelpOfferCount: authorUnreviewedHelpOfferCount,
    viewerBlocked: blocked,
    isAwaitingAuthorReview: isAwaitingAuthorReview,
    rowHarmony: phaseResult?.rowHarmony ?? BeaconPhaseRowHarmony.empty,
  );
  return isBeaconYouRowVisible(input: input);
}

/// [tableRowWidth] is the full metadata table width (not body column).
bool beaconYouCompactSurface(BuildContext context, double tableRowWidth) =>
    context.windowClass == WindowClass.compact && tableRowWidth < 320;
