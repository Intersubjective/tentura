import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/open_blocker_cue.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_input_builders.dart';
import 'package:tentura/ui/widget/coordination_item_presenter.dart';

enum BeaconYouEmptyFallback {
  hidden,
  waitingOnOthers,
  noOpenItems,
  awaitingAuthorReview,
  noInfo,
  closed,
}

bool viewerAwaitingAuthorHelpOfferReview({
  required bool isAuthorOrSteward,
  required CoordinationResponseType? viewerOfferAuthorResponse,
  required bool viewerHasActiveHelpOffer,
}) =>
    !isAuthorOrSteward &&
    viewerHasActiveHelpOffer &&
    viewerOfferAuthorResponse == null;

BeaconYouEmptyFallback deriveBeaconYouEmptyFallback({
  required BeaconLifecycle lifecycle,
  required bool isAuthorOrSteward,
  required int othersOpenCount,
  required bool compactSurface,
  required bool hasPersonalObligation,
  bool isAwaitingAuthorReview = false,
  BeaconPhaseRowHarmony rowHarmony = BeaconPhaseRowHarmony.empty,
}) {
  if (lifecycle == BeaconLifecycle.closed ||
      lifecycle == BeaconLifecycle.deleted) {
    return BeaconYouEmptyFallback.closed;
  }
  if (rowHarmony.suppressYouAwaitingAuthor && isAuthorOrSteward) {
    return BeaconYouEmptyFallback.waitingOnOthers;
  }
  if (othersOpenCount > 0) {
    return BeaconYouEmptyFallback.waitingOnOthers;
  }
  if (isAwaitingAuthorReview) {
    return BeaconYouEmptyFallback.awaitingAuthorReview;
  }
  if (!isAuthorOrSteward &&
      lifecycle == BeaconLifecycle.open &&
      !compactSurface) {
    return BeaconYouEmptyFallback.noInfo;
  }
  if (compactSurface && !hasPersonalObligation) {
    return BeaconYouEmptyFallback.hidden;
  }
  return BeaconYouEmptyFallback.noOpenItems;
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
  });

  final String label;
  final String semanticsLabel;
  final Widget? raiserAvatar;
  final String? elapsedLabel;
}

@immutable
class BeaconYouSegmentPresentation {
  const BeaconYouSegmentPresentation({
    required this.icon,
    required this.count,
    this.label,
    this.newCount = 0,
  });

  final IconData icon;
  final int count;
  final String? label;
  final int newCount;
}

@immutable
class BeaconYouPresentation {
  const BeaconYouPresentation.segments({
    required this.segments,
    this.blockedSegment,
  })  : fallbackText = null,
        blockedOnly = false;

  const BeaconYouPresentation.blockedOnly({
    required this.blockedSegment,
  })  : segments = const [],
        fallbackText = null,
        blockedOnly = true;

  const BeaconYouPresentation.fallback({
    required this.fallbackText,
  })  : segments = const [],
        blockedSegment = null,
        blockedOnly = false;

  const BeaconYouPresentation.hidden()
      : segments = const [],
        fallbackText = null,
        blockedSegment = null,
        blockedOnly = false;

  final List<BeaconYouSegmentPresentation> segments;
  final BeaconYouBlockedSegmentPresentation? blockedSegment;
  final String? fallbackText;
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
  required BeaconYouEmptyFallback emptyFallback,
  required bool showNewBadges,
  BeaconYouBlockedSegmentPresentation? blockedSegment,
}) {
  if (blockedSegment != null && !responsibility.hasAny) {
    return BeaconYouPresentation.blockedOnly(blockedSegment: blockedSegment);
  }

  if (responsibility.hasAny) {
    final segments = responsibility.orderedEntries
        .map(
          (entry) => BeaconYouSegmentPresentation(
            icon: coordinationKindIcon(entry.kind),
            count: entry.open,
            label: collapse ? null : _kindLabel(l10n, entry.kind, entry.open),
            newCount: showNewBadges ? entry.newCount : 0,
          ),
        )
        .toList(growable: false);
    return BeaconYouPresentation.segments(
      segments: segments,
      blockedSegment: blockedSegment,
    );
  }

  return switch (emptyFallback) {
    BeaconYouEmptyFallback.hidden => const BeaconYouPresentation.hidden(),
    BeaconYouEmptyFallback.waitingOnOthers => BeaconYouPresentation.fallback(
        fallbackText: l10n.beaconYouWaitingOnOthers,
      ),
    BeaconYouEmptyFallback.noOpenItems => BeaconYouPresentation.fallback(
        fallbackText: l10n.beaconYouNoOpenItems,
      ),
    BeaconYouEmptyFallback.awaitingAuthorReview =>
      BeaconYouPresentation.fallback(
        fallbackText: l10n.beaconYouOfferSent,
      ),
    BeaconYouEmptyFallback.noInfo => BeaconYouPresentation.fallback(
        fallbackText: l10n.beaconYouNoInfo,
      ),
    BeaconYouEmptyFallback.closed => BeaconYouPresentation.fallback(
        fallbackText: l10n.beaconYouClosed,
      ),
  };
}

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
  return deriveBeaconYouEmptyFallback(
    lifecycle: beacon.lifecycle,
    isAuthorOrSteward: isAuthorOrSteward,
    othersOpenCount: responsibility.othersOpenCount,
    compactSurface: compactSurface,
    hasPersonalObligation: responsibility.hasAny || blocked,
    isAwaitingAuthorReview: isAwaitingAuthorReview,
    rowHarmony: phaseResult?.rowHarmony ?? BeaconPhaseRowHarmony.empty,
  );
}

/// Whether the YOU metadata table row should be emitted (vs omitted entirely).
bool isBeaconYouMetadataVisible({
  required Beacon beacon,
  required CoordinationResponsibility responsibility,
  required bool isAuthorOrSteward,
  required bool compactSurface,
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
  final emptyFallback = deriveBeaconYouEmptyFallback(
    lifecycle: beacon.lifecycle,
    isAuthorOrSteward: isAuthorOrSteward,
    othersOpenCount: responsibility.othersOpenCount,
    compactSurface: compactSurface,
    hasPersonalObligation: false,
    isAwaitingAuthorReview: isAwaitingAuthorReview,
    rowHarmony: phaseResult?.rowHarmony ?? BeaconPhaseRowHarmony.empty,
  );
  return emptyFallback != BeaconYouEmptyFallback.hidden;
}

/// [tableRowWidth] is the full metadata table width (not body column).
bool beaconYouCompactSurface(BuildContext context, double tableRowWidth) =>
    context.windowClass == WindowClass.compact && tableRowWidth < 320;
