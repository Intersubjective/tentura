import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/coordination_item_presenter.dart';

enum BeaconYouEmptyFallback {
  hidden,
  waitingOnOthers,
  noOpenItems,
  enoughHelp,
  closed,
}

BeaconYouEmptyFallback deriveBeaconYouEmptyFallback({
  required BeaconLifecycle lifecycle,
  required bool isAuthorOrSteward,
  required int othersOpenCount,
  required bool compactSurface,
}) {
  if (lifecycle == BeaconLifecycle.closed ||
      lifecycle == BeaconLifecycle.closedReviewComplete ||
      lifecycle == BeaconLifecycle.deleted) {
    return BeaconYouEmptyFallback.closed;
  }
  if (othersOpenCount > 0) {
    return BeaconYouEmptyFallback.waitingOnOthers;
  }
  if (!isAuthorOrSteward &&
      lifecycle == BeaconLifecycle.open &&
      !compactSurface) {
    return BeaconYouEmptyFallback.enoughHelp;
  }
  if (compactSurface) {
    return BeaconYouEmptyFallback.hidden;
  }
  return BeaconYouEmptyFallback.noOpenItems;
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
  }) : fallbackText = null;

  const BeaconYouPresentation.fallback({
    required this.fallbackText,
  }) : segments = const [];

  const BeaconYouPresentation.hidden()
      : segments = const [],
        fallbackText = null;

  final List<BeaconYouSegmentPresentation> segments;
  final String? fallbackText;

  bool get isHidden =>
      segments.isEmpty && (fallbackText == null || fallbackText!.isEmpty);
}

BeaconYouPresentation buildBeaconYouPresentation(
  L10n l10n,
  CoordinationResponsibility responsibility, {
  required bool collapse,
  required BeaconYouEmptyFallback emptyFallback,
  required bool showNewBadges,
}) {
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
    return BeaconYouPresentation.segments(segments: segments);
  }

  return switch (emptyFallback) {
    BeaconYouEmptyFallback.hidden => const BeaconYouPresentation.hidden(),
    BeaconYouEmptyFallback.waitingOnOthers => BeaconYouPresentation.fallback(
        fallbackText: l10n.beaconYouWaitingOnOthers,
      ),
    BeaconYouEmptyFallback.noOpenItems => BeaconYouPresentation.fallback(
        fallbackText: l10n.beaconYouNoOpenItems,
      ),
    BeaconYouEmptyFallback.enoughHelp => BeaconYouPresentation.fallback(
        fallbackText: l10n.beaconYouEnoughHelp,
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
}) {
  return deriveBeaconYouEmptyFallback(
    lifecycle: beacon.lifecycle,
    isAuthorOrSteward: isAuthorOrSteward,
    othersOpenCount: responsibility.othersOpenCount,
    compactSurface: compactSurface,
  );
}
