import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';

import 'beacon_anchor_status.dart';

/// AppBar title: beacon identity tile, elided title, single-line anchor status.
///
/// Optional [onTap] makes the whole row (icon + title + status) a surface switch
/// control; [tooltipMessage] explains the action (including when [onTap] is
/// null but room access is unavailable).
class BeaconViewAppBarTitle extends StatelessWidget {
  const BeaconViewAppBarTitle({
    required this.beacon,
    required this.activeCommitCount,
    required this.l10n,
    this.onTap,
    this.tooltipMessage,
    this.roomUnreadBadgeCount,
    super.key,
  });

  final Beacon beacon;
  final int activeCommitCount;
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
    final statusLine =
        beaconAnchorStatusLine(l10n, beacon, activeCommitCount);
    final tone = beaconAnchorStatusTone(beacon.coordinationStatus);
    final titleText =
        beacon.title.isEmpty ? l10n.beaconViewTitle : beacon.title;

    final semanticsLabel = '$titleText. $statusLine';

    Widget row = Row(
      children: [
        ExcludeSemantics(
          child: BeaconIdentityTile(beacon: beacon, size: _identitySize),
        ),
        const SizedBox(width: 8),
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
                style: TenturaText.title(scheme.onSurface),
              ),
              TenturaStatusText(
                statusLine,
                tone: tone,
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
      row = Badge(
        label: Text('$unread'),
        child: row,
      );
    }

    final tip = tooltipMessage;
    if (tip != null && tip.isNotEmpty) {
      row = Tooltip(message: tip, child: row);
    }

    return Semantics(
      button: onTap != null,
      label: semanticsLabel,
      hint: onTap != null ? tooltipMessage : null,
      child: row,
    );
  }
}
