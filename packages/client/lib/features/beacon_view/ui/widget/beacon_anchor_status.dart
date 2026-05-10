import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Semantic tone for the operational "anchor" status line (coordination + commitments).
TenturaTone beaconAnchorStatusTone(BeaconCoordinationStatus s) => switch (s) {
      BeaconCoordinationStatus.noCommitmentsYet => TenturaTone.neutral,
      BeaconCoordinationStatus.commitmentsWaitingForReview => TenturaTone.info,
      BeaconCoordinationStatus.moreOrDifferentHelpNeeded => TenturaTone.warn,
      BeaconCoordinationStatus.enoughHelpCommitted => TenturaTone.good,
    };

/// Localized anchor line: coordination label · commitments fragment.
String beaconAnchorStatusLine(
  L10n l10n,
  Beacon beacon,
  int activeCommitCount,
) {
  final coord = coordinationStatusLabel(l10n, beacon.coordinationStatus);
  final committedPart = activeCommitCount == 0
      ? l10n.beaconHeaderNoCommitments
      : l10n.beaconHeaderCommitmentsCount(activeCommitCount);
  return '$coord · $committedPart';
}
