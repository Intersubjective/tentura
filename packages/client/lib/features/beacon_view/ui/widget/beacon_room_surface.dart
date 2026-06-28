import 'package:flutter/material.dart';

import 'package:tentura/features/beacon_room/ui/widget/beacon_room_body.dart';

/// Room surface embedded under beacon detail (chat only).
///
/// NOW/YOU coordination context lives on the beacon Items tab.
class BeaconRoomSurface extends StatelessWidget {
  const BeaconRoomSurface({
    super.key,
    required this.beaconAuthorId,
    this.onCoordinationSaved,
  });

  final String beaconAuthorId;
  final VoidCallback? onCoordinationSaved;

  @override
  Widget build(BuildContext context) {
    return BeaconRoomBody(
      beaconAuthorId: beaconAuthorId,
      onCoordinationSaved: onCoordinationSaved,
    );
  }
}
