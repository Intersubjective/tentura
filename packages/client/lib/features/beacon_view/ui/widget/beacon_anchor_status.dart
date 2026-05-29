import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Semantic tone for the operational "anchor" status line (coordination + help offers).
TenturaTone beaconAnchorStatusTone(BeaconCoordinationStatus s) => switch (s) {
      BeaconCoordinationStatus.noHelpOffersYet => TenturaTone.neutral,
      BeaconCoordinationStatus.helpOffersWaitingForReview => TenturaTone.info,
      BeaconCoordinationStatus.moreOrDifferentHelpNeeded => TenturaTone.warn,
      BeaconCoordinationStatus.enoughHelpOffered => TenturaTone.good,
    };

/// Localized anchor line: coordination label · help offers fragment.
String beaconAnchorStatusLine(
  L10n l10n,
  Beacon beacon,
  int activeHelpOfferCount,
) {
  final coord = coordinationStatusLabel(l10n, beacon.coordinationStatus);
  final helpOfferedPart = activeHelpOfferCount == 0
      ? l10n.beaconHeaderNoHelpOffers
      : l10n.beaconHeaderHelpOffersCount(activeHelpOfferCount);
  return '$coord · $helpOfferedPart';
}

/// Terse anchor line for compact surfaces (e.g. AppBar): ALL-CAPS code · count.
String beaconAnchorStatusLineShort(
  Beacon beacon,
  int activeHelpOfferCount,
) =>
    switch (beacon.coordinationStatus) {
      BeaconCoordinationStatus.noHelpOffersYet => 'IDLE',
      BeaconCoordinationStatus.helpOffersWaitingForReview =>
        activeHelpOfferCount > 0 ? 'REVIEW · $activeHelpOfferCount' : 'REVIEW',
      BeaconCoordinationStatus.moreOrDifferentHelpNeeded =>
        activeHelpOfferCount > 0 ? 'GAP · $activeHelpOfferCount' : 'GAP',
      BeaconCoordinationStatus.enoughHelpOffered =>
        activeHelpOfferCount > 0 ? 'OK · $activeHelpOfferCount' : 'OK',
    };
