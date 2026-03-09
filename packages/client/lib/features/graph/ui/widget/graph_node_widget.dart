import 'package:flutter/material.dart';

import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/beacon_image.dart';

import '../../domain/entity/node_details.dart';

class GraphNodeWidget extends StatelessWidget {
  const GraphNodeWidget({
    required this.nodeDetails,
    this.withRating = false,
    this.onDoubleTap,
    this.onTap,
    super.key,
  });

  final bool withRating;
  final NodeDetails nodeDetails;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;

  @override
  Widget build(BuildContext context) {
    final widget = SizedBox.square(
      dimension: nodeDetails.size,
      child: switch (nodeDetails) {
        //
        final UserNode userNode => AvatarRated(
          profile: userNode.user,
          size: nodeDetails.size,
          withRating: withRating,
        ),
        //
        final BeaconNode beaconNode => BeaconImage(
          beacon: beaconNode.beacon,
        ),
      },
    );
    return onTap == null && onDoubleTap == null
        ? widget
        : GestureDetector(
            onTap: onTap,
            onDoubleTap: onDoubleTap,
            child: widget,
          );
  }
}
