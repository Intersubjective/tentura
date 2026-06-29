import 'package:flutter/material.dart';

import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/design_system/components/tentura_avatar.dart';
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
            final isSelf = SelfUserHighlight.profileIsSelf(
              userNode.user,
              state.profile.id,
            );
            final core = TenturaAvatar(
              profile: userNode.user,
              size: s,
              withRating: withRating,
              isSelf: isSelf,
            );
            Widget result = core;
            if (userNode.isHelpOfferer) {
              result = _HelpOffererRing(size: s, child: result);
            }
            return result;
          },
        ),
        final BeaconNode beaconNode => BeaconImage(
          beacon: beaconNode.beacon,
        ),
        final GenealogyUserNode genealogyUser => TenturaAvatar(
          profile: genealogyUser.user,
          size: nodeDetails.size,
          withRating: withRating,
          isSelf: false,
        ),
        final GenealogyDeletedNode _ => CircleAvatar(
          radius: nodeDetails.size / 2,
          child: Icon(
            Icons.person_off_outlined,
            size: nodeDetails.size * 0.45,
          ),
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

/// Distinct accent ring for users who offered help for the focused beacon
/// (forwards graph). Drawn outside the avatar so it does not collide with the
/// self-user ring (which uses [ColorScheme.primary]).
class _HelpOffererRing extends StatelessWidget {
  const _HelpOffererRing({required this.size, required this.child});

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
              painter: _HelpOffererRingPainter(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpOffererRingPainter extends CustomPainter {
  _HelpOffererRingPainter({required this.color});

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
  bool shouldRepaint(covariant _HelpOffererRingPainter oldDelegate) =>
      oldDelegate.color != color;
}
