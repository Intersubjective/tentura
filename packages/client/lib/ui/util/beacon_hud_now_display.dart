import 'package:flutter/foundation.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Operational HUD NOW block: current line (or placeholder) plus optional blocker.
@immutable
class BeaconHudNowDisplay {
  const BeaconHudNowDisplay({
    required this.primaryText,
    this.blockerText,
    this.isPlaceholder = false,
  });

  final String primaryText;
  final String? blockerText;
  final bool isPlaceholder;
}

/// NOW row for My desk cards from beacon lifecycle + room context batch hints.
BeaconHudNowDisplay myWorkDeskNowDisplay(
  L10n l10n, {
  required Beacon beacon,
  required String roomCurrentLine,
  String openBlockerTitle = '',
}) {
  if (beacon.status == BeaconStatus.deleted) {
    return BeaconHudNowDisplay(primaryText: l10n.beaconHudBeaconUnavailable);
  }

  if (beacon.status == BeaconStatus.closed ||
      beacon.status == BeaconStatus.cancelled) {
    return BeaconHudNowDisplay(primaryText: l10n.beaconHudClosedSummary);
  }

  if (beacon.status == BeaconStatus.reviewOpen) {
    // #487 — in Final check the coordination label is the neutral "—": a
    // placeholder, so the card hides the row as it does with no next step.
    return BeaconHudNowDisplay(
      primaryText: coordinationStatusLabel(l10n, beacon.status),
      isPlaceholder: true,
    );
  }

  final blockerTitle = openBlockerTitle.trim();
  final blockerText = blockerTitle.isNotEmpty
      ? l10n.beaconHudNowBlocked(blockerTitle)
      : null;

  final currentLine = roomCurrentLine.trim();
  if (currentLine.isNotEmpty) {
    return BeaconHudNowDisplay(
      primaryText: clipBeaconRoomCurrentLine(currentLine),
      blockerText: blockerText,
    );
  }

  return BeaconHudNowDisplay(
    primaryText: l10n.beaconHudNoCurrentLine,
    blockerText: blockerText,
    isPlaceholder: true,
  );
}

/// The room's pinned open-blocker line, or null when nothing is blocked.
String? beaconRoomBlockerText(
  L10n l10n, {
  required BeaconRoomState? roomState,
  CoordinationItem? openBlocker,
}) {
  final blockerTitle =
      roomState?.openBlockerTitle?.trim() ?? openBlocker?.title.trim();
  return blockerTitle != null && blockerTitle.isNotEmpty
      ? l10n.beaconHudNowBlocked(blockerTitle)
      : null;
}
