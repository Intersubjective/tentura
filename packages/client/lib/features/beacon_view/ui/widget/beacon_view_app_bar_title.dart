import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';

import 'beacon_anchor_status.dart';

/// AppBar title: beacon identity tile, elided title, single-line anchor status.
class BeaconViewAppBarTitle extends StatelessWidget {
  const BeaconViewAppBarTitle({
    required this.beacon,
    required this.activeCommitCount,
    required this.l10n,
    super.key,
  });

  final Beacon beacon;
  final int activeCommitCount;
  final L10n l10n;

  static const double _identitySize = 32;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusLine =
        beaconAnchorStatusLine(l10n, beacon, activeCommitCount);
    final tone = beaconAnchorStatusTone(beacon.coordinationStatus);
    final titleText =
        beacon.title.isEmpty ? l10n.beaconViewTitle : beacon.title;

    return Semantics(
      label: '$titleText. $statusLine',
      child: Row(
        children: [
          BeaconIdentityTile(beacon: beacon, size: _identitySize),
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
      ),
    );
  }
}
