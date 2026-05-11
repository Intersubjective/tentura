import 'package:flutter/material.dart';

import 'package:tentura/features/beacon_room/ui/widget/beacon_room_body.dart';

/// Room surface embedded under beacon detail.
///
/// Coordination strips are hidden; the host screen supplies navigation and
/// beacon context.
class BeaconRoomSurface extends StatelessWidget {
  const BeaconRoomSurface({super.key});

  @override
  Widget build(BuildContext context) {
    return const BeaconRoomBody(hideCoordinationStrips: true);
  }
}
