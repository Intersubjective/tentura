import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

/// Legacy route stub — `/beacon/room/:id` redirects in [RootRouter].
@RoutePage()
class BeaconRoomScreen extends StatelessWidget {
  const BeaconRoomScreen({
    @PathParam('id') this.beaconId = '',
    super.key,
  });

  final String beaconId;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
