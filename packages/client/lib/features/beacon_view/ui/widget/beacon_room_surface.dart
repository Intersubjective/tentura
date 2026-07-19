import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/beacon_room/ui/widget/beacon_room_body.dart';
import 'package:tentura/features/beacon_view/ui/widget/closed_request_banner.dart';

/// Room surface embedded under beacon detail (chat only).
///
/// NOW/YOU coordination context lives on the beacon Items tab.
class BeaconRoomSurface extends StatelessWidget {
  const BeaconRoomSurface({
    required this.beaconAuthorId,
    required this.beacon,
    super.key,
    this.onCoordinationSaved,
  });

  final String beaconAuthorId;
  final Beacon beacon;
  final VoidCallback? onCoordinationSaved;

  @override
  Widget build(BuildContext context) {
    return TenturaChatColumn(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClosedRequestBanner(beacon: beacon),
          Expanded(
            child: BeaconRoomBody(
              beaconAuthorId: beaconAuthorId,
              onCoordinationSaved: onCoordinationSaved,
            ),
          ),
        ],
      ),
    );
  }
}
