import 'package:flutter/material.dart';

import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/beacon_image.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

import '../../domain/entity/node_details.dart';

class GraphNodeWidget extends StatelessWidget {
  const GraphNodeWidget({
    required this.nodeDetails,
    this.withRating = false,
    this.onTap,
    super.key,
  });

  final bool withRating;
  final NodeDetails nodeDetails;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final widget = SizedBox.square(
      dimension: nodeDetails.size,
      child: switch (nodeDetails) {
        final UserNode userNode => BlocBuilder<ProfileCubit, ProfileState>(
          buildWhen: (p, c) => p.profile.id != c.profile.id,
          builder: (context, state) {
            final s = nodeDetails.size;
            final core = AvatarRated(
              profile: userNode.user,
              size: s,
              withRating: withRating,
            );
            final isSelf = SelfUserHighlight.profileIsSelf(
              userNode.user,
              state.profile.id,
            );
            if (s > 48 || !isSelf) {
              return core;
            }
            return SelfUserHighlight.wrapSmallAvatar(
              context,
              avatarSize: s,
              isSelf: isSelf,
              child: core,
            );
          },
        ),
        final BeaconNode beaconNode => BeaconImage(
          beacon: beaconNode.beacon,
        ),
      },
    );
    return onTap == null
        ? widget
        : GestureDetector(
            onTap: onTap,
            child: widget,
          );
  }
}
