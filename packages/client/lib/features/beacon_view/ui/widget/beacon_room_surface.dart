import 'package:flutter/material.dart';

import 'package:tentura/features/beacon_room/ui/widget/beacon_room_body.dart';

/// Room surface embedded under beacon detail.
///
/// Coordination strips match the standalone room: plan, pinned facts, and
/// your row stay visible so context is not hidden behind a mode toggle.
class BeaconRoomSurface extends StatelessWidget {
  const BeaconRoomSurface({super.key});

  @override
  Widget build(BuildContext context) {
    return const BeaconRoomBody();
  }
}
