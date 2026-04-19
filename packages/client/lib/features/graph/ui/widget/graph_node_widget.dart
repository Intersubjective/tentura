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
            Widget result = core;
            if (userNode.isCommitter) {
              result = _CommitterRing(size: s, child: result);
            }
            if (isSelf && s <= 48) {
              result = SelfUserHighlight.wrapSmallAvatar(
                context,
                avatarSize: s,
                isSelf: isSelf,
                child: result,
              );
            }
            return result;
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

/// Distinct accent ring for users who committed to the focused beacon
/// (forwards graph). Drawn outside the avatar so it does not collide with the
/// self-user ring (which uses [ColorScheme.primary]).
class _CommitterRing extends StatelessWidget {
  const _CommitterRing({required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.tertiary;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: child),
          IgnorePointer(
            child: CustomPaint(
              painter: _CommitterRingPainter(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _CommitterRingPainter extends CustomPainter {
  _CommitterRingPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.0;
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2 - stroke / 2;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..isAntiAlias = true;
    canvas.drawCircle(c, r, paint);
  }

  @override
  bool shouldRepaint(covariant _CommitterRingPainter oldDelegate) =>
      oldDelegate.color != color;
}
