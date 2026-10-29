import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_cover.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_presenter.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';

/// AppBar title: beacon identity tile, elided title, single-line anchor status.
///
/// Optional [onTap] makes the whole row (icon + title + status) a surface switch
/// control; [tooltipMessage] explains the action (including when [onTap] is
/// null but room access is unavailable).
class BeaconViewAppBarTitle extends StatelessWidget {
  const BeaconViewAppBarTitle({
    required this.beacon,
    required this.phaseStatus,
    required this.l10n,
    this.showBeaconContent = true,
    this.showStatus = true,
    this.onTap,
    this.tooltipMessage,
    this.roomUnreadBadgeCount,
    super.key,
  });

  final Beacon beacon;

  /// When false (loading / gated null), do not render beacon title or identity.
  final bool showBeaconContent;

  /// False when the status is shown by [BeaconViewStatusBottom] instead.
  final bool showStatus;

  /// Single-line operational status (dual-tone when slot2 is set).
  final BeaconPhaseStatusPresentation phaseStatus;

  final L10n l10n;

  /// Switch beacon surface (status ↔ room). Null ⇒ not interactive.
  final VoidCallback? onTap;

  /// Tooltip for switch affordance (shown even when [onTap] is null if set).
  final String? tooltipMessage;

  /// When non-null and positive, shows unread count on the title row (status
  /// surface / room available).
  final int? roomUnreadBadgeCount;

  static const double _identitySize = 32;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusLine = phaseStatus.statusLine;

    if (!showBeaconContent) {
      final label = l10n.beaconViewTitle;
      return Semantics(
        header: true,
        label: label,
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TenturaText.titleSmall(scheme.onSurface),
        ),
      );
    }

    final titleText = beacon.title.isEmpty
        ? l10n.beaconViewTitle
        : beacon.title;

    final semanticsLabel = '$titleText. $statusLine';

    // A neutral tile is a placeholder, not identity: give its width to the
    // title instead.
    final showIdentity = beacon.identity is! BeaconIdentityNeutral;

    Widget row = Row(
      children: [
        if (showIdentity) ...[
          ExcludeSemantics(
            child: BeaconIdentityTile(beacon: beacon, size: _identitySize),
          ),
          SizedBox(width: context.tt.iconTextGap),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                titleText,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TenturaText.titleSmall(scheme.onSurface),
              ),
              if (showStatus)
                TenturaStatusLine(
                  slot1: phaseStatus.slot1,
                  slot2: phaseStatus.slot2,
                  slot1Tone: phaseStatus.slot1Tone,
                  slot2Tone: phaseStatus.slot2Tone,
                ),
            ],
          ),
        ),
      ],
    );

    if (onTap != null) {
      row = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: row,
        ),
      );
    }

    final unread = roomUnreadBadgeCount;
    if (unread != null && unread > 0) {
      row = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(child: row),
          SizedBox(width: context.tt.iconTextGap),
          TenturaCountBadge(
            count: unread,
            backgroundColor: context.tt.info,
          ),
        ],
      );
    }

    // Without a switch hint, the tooltip carries the full title the row
    // may have elided.
    final tip = tooltipMessage;
    final hasTip = tip != null && tip.isNotEmpty;
    row = Tooltip(
      message: hasTip ? tip : titleText,
      // The row's own label already reads the title.
      excludeFromSemantics: !hasTip,
      child: row,
    );

    return Semantics(
      button: onTap != null,
      label: semanticsLabel,
      hint: onTap != null ? tooltipMessage : null,
      child: row,
    );
  }
}

/// The whole status line under the app-bar row, wrapped to as many lines as it
/// needs, for a status too long for the one line beside the title (#486): the
/// guidance at its end is never cut. The bar is a fixed-height widget, so the
/// height is measured up front.
class BeaconViewStatusBottom extends StatelessWidget
    implements PreferredSizeWidget {
  const BeaconViewStatusBottom._({
    required this.phaseStatus,
    required this.height,
  });

  /// The bottom for [phaseStatus], or null when it fits on the title's own
  /// line and [BeaconViewAppBarTitle] keeps showing it.
  static BeaconViewStatusBottom? maybeOf(
    BuildContext context,
    BeaconPhaseStatusPresentation phaseStatus,
  ) {
    final tt = context.tt;
    final width = MediaQuery.sizeOf(context).width - 2 * tt.screenHPadding;
    // Room beside the title: back, ⋮ and the identity tile with their gaps.
    final titleSlot =
        width -
        3 * kMinInteractiveDimension -
        BeaconViewAppBarTitle._identitySize -
        3 * tt.iconTextGap;

    (int lines, double height) measure(double maxWidth) {
      final painter = TextPainter(
        text: TextSpan(
          text: phaseStatus.statusLine,
          style: TenturaText.status(Theme.of(context).colorScheme.onSurface),
        ),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
      )..layout(maxWidth: maxWidth);
      final result = (painter.computeLineMetrics().length, painter.height);
      painter.dispose();
      return result;
    }

    if (measure(titleSlot).$1 == 1) return null;
    return BeaconViewStatusBottom._(
      phaseStatus: phaseStatus,
      height: measure(width).$2,
    );
  }

  final BeaconPhaseStatusPresentation phaseStatus;
  final double height;

  @override
  Size get preferredSize => Size.fromHeight(height);

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.topStart,
    child: TenturaStatusLine(
      slot1: phaseStatus.slot1,
      slot2: phaseStatus.slot2,
      slot1Tone: phaseStatus.slot1Tone,
      slot2Tone: phaseStatus.slot2Tone,
      overflow: TextOverflow.visible,
    ),
  );
}
