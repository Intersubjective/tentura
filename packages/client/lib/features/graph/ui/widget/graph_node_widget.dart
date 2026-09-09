import 'package:flutter/material.dart';

import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/design_system/components/tentura_count_badge.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/constellation/domain/constellation_request_identity.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

import '../../domain/entity/node_details.dart';

class GraphNodeWidget extends StatelessWidget {
  const GraphNodeWidget({
    required this.nodeDetails,
    this.withRating = false,
    this.isSelf = false,
    this.isOrigin = false,
    this.isFocused = false,
    this.hiddenNeighborCount,
    this.onTap,
    super.key,
  });

  /// [CustomPaint] key for the selection ring when [isFocused] is true.
  static const focusRingKey = ValueKey<String>('graphNodeFocusRing');

  final bool withRating;
  final bool isSelf;
  final bool isOrigin;
  final bool isFocused;
  final int? hiddenNeighborCount;
  final NodeDetails nodeDetails;
  final VoidCallback? onTap;

  static String semanticLabel(L10n l10n, NodeDetails details) {
    return switch (details) {
      UserNode(:final user) => user.displayLabel(l10n.unknownPerson),
      GenealogyUserNode(:final user) => user.displayLabel(l10n.unknownPerson),
      BeaconNode(:final beacon) => _beaconSemanticLabel(l10n, beacon),
      GenealogyDeletedNode(:final label) =>
        label.trim().isNotEmpty ? label : l10n.inviteGenealogyAnonymousNode,
      FieldPersonNode(:final person) => person.displayLabel(l10n.unknownPerson),
      FieldRequestNode(:final request) =>
        request.title.trim().isEmpty ? l10n.beaconViewTitle : request.title,
      _ => '',
    };
  }

  static String _beaconSemanticLabel(L10n l10n, Beacon beacon) {
    final title = beacon.title.trim();
    if (title.isEmpty) {
      return l10n.beaconViewTitle;
    }
    return '${l10n.beaconViewTitle}: $title';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final node = switch (nodeDetails) {
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
      final BeaconNode beaconNode => BeaconIdentityTile(
        beacon: beaconNode.beacon,
        size: nodeDetails.size,
      ),
      final GenealogyUserNode genealogyUser => TenturaAvatar(
        profile: genealogyUser.user,
        size: nodeDetails.size,
        // Self never gets the eye/mutual-friend or rating overlay — those
        // are relative-to-viewer signals that don't apply to one's own node.
        withRating: withRating && !isSelf,
        isSelf: isSelf,
      ),
      final GenealogyDeletedNode _ => CircleAvatar(
        radius: nodeDetails.size / 2,
        child: Icon(
          Icons.person_off_outlined,
          size: nodeDetails.size * 0.45,
        ),
      ),
      FieldPersonNode(:final person) => TenturaAvatar(
        profile: person,
        size: nodeDetails.size,
        withRating: withRating,
        isSelf: isSelf,
      ),
      FieldRequestNode(:final request) => BeaconIdentityTile(
        beacon: constellationRequestAsIdentityBeacon(request),
        size: nodeDetails.size,
      ),
    };
    final useSquareFocus =
        nodeDetails is BeaconNode || nodeDetails is FieldRequestNode;
    var decorated = isOrigin && !isSelf
        ? _OriginRing(size: nodeDetails.size, child: node)
        : node;
    // Focus is outermost so selection stays visible; painter is inset so it
    // does not coincide with self / origin / help-offerer rings.
    if (isFocused) {
      decorated = _FocusRing(
        size: nodeDetails.size,
        square: useSquareFocus,
        child: decorated,
      );
    }
    final widget = SizedBox.square(
      dimension: nodeDetails.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: decorated),
          if (hiddenNeighborCount != null && hiddenNeighborCount! > 0)
            Positioned(
              top: 0,
              right: 0,
              child: TenturaCountBadge(
                count: hiddenNeighborCount!,
                backgroundColor: Theme.of(context).colorScheme.primary,
              ),
            ),
        ],
      ),
    );
    if (onTap == null) {
      return widget;
    }
    return GestureDetector(
      onTap: onTap,
      child: Semantics(
        button: true,
        selected: isFocused,
        label: semanticLabel(l10n, nodeDetails),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: ExcludeSemantics(
            child: widget,
          ),
        ),
      ),
    );
  }
}

/// Selection ring for the node that owns [GraphState.focus] / the action panel.
///
/// Always inset so it remains readable under self halo, origin, or help-offerer
/// rings that paint at the outer radius.
class _FocusRing extends StatelessWidget {
  const _FocusRing({
    required this.size,
    required this.child,
    this.square = false,
  });

  final double size;
  final Widget child;
  final bool square;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.secondary;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: child),
          IgnorePointer(
            child: CustomPaint(
              key: GraphNodeWidget.focusRingKey,
              painter: _FocusRingPainter(color: color, square: square),
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  _FocusRingPainter({required this.color, required this.square});

  final Color color;
  final bool square;

  static const stroke = 3.0;
  static const inset = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..isAntiAlias = true;
    if (square) {
      final radius = size.shortestSide * 0.2;
      final rect = Rect.fromLTWH(
        inset + stroke / 2,
        inset + stroke / 2,
        size.width - (inset + stroke / 2) * 2,
        size.height - (inset + stroke / 2) * 2,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        paint,
      );
      return;
    }
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2 - stroke / 2 - inset;
    canvas.drawCircle(c, r, paint);
  }

  @override
  bool shouldRepaint(covariant _FocusRingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.square != square;
}

/// Distinct primary ring for the graph origin (ego / genealogy viewer).
class _OriginRing extends StatelessWidget {
  const _OriginRing({required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(child: child),
          IgnorePointer(
            child: CustomPaint(
              painter: _OriginRingPainter(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _OriginRingPainter extends CustomPainter {
  _OriginRingPainter({required this.color});

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
  bool shouldRepaint(covariant _OriginRingPainter oldDelegate) =>
      oldDelegate.color != color;
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
