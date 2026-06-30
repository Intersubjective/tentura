import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_room/ui/widget/beacon_room_body.dart';

/// Room surface embedded under beacon detail (chat only).
///
/// NOW/YOU coordination context lives on the beacon Items tab.
class BeaconRoomSurface extends StatelessWidget {
  const BeaconRoomSurface({
    required this.beaconAuthorId,
    super.key,
    this.onCoordinationSaved,
  });

  final String beaconAuthorId;
  final VoidCallback? onCoordinationSaved;

  @override
  Widget build(BuildContext context) {
    return TenturaChatColumn(
      child: BeaconRoomBody(
        beaconAuthorId: beaconAuthorId,
        onCoordinationSaved: onCoordinationSaved,
      ),
    );
  }
}
