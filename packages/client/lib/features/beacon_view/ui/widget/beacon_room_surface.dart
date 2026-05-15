import 'package:flutter/material.dart';

import 'package:tentura/features/beacon_room/ui/widget/beacon_room_body.dart';

/// Room surface embedded under beacon detail (chat only).
///
/// NOW/YOU coordination context lives on the beacon Items tab.
class BeaconRoomSurface extends StatelessWidget {
  const BeaconRoomSurface({super.key});

  @override
  Widget build(BuildContext context) {
    return const BeaconRoomBody();
  }
}
