import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

import '../../domain/constellation_trust_chain.dart';
import '../utils/constellation_presentation_frame.dart';
import 'constellation_node_ring_layer.dart';

/// One short pulse when a «new on your Field» ring first appears (#898).
const kConstellationFieldNewPulseDuration = Duration(milliseconds: 450);

/// Viewport-space accent rings for people new on the viewer's Field (#898).
class ConstellationFieldNewRingLayer extends StatefulWidget {
  const ConstellationFieldNewRingLayer({
    required this.frame,
    required this.newGraphIds,
    required this.accentColor,
    this.dimmedGraphIds = const {},
    super.key,
  });

  final ConstellationPresentationFrame frame;
  final Set<GraphNodeId> newGraphIds;
  final Set<GraphNodeId> dimmedGraphIds;
  final Color accentColor;

  @override
  State<ConstellationFieldNewRingLayer> createState() =>
      _ConstellationFieldNewRingLayerState();
}

class _ConstellationFieldNewRingLayerState
    extends State<ConstellationFieldNewRingLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: kConstellationFieldNewPulseDuration,
  );
  late final Animation<double> _ease = CurvedAnimation(
    parent: _pulse,
    curve: Curves.easeOut,
  );
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _maybePulse();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _maybePulse();
  }

  @override
  void didUpdateWidget(ConstellationFieldNewRingLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybePulse();
  }

  void _maybePulse() {
    if (_reduceMotion || widget.newGraphIds.isEmpty || _pulse.isAnimating) {
      return;
    }
    if (_pulse.value == 0) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.newGraphIds.isEmpty) {
      return const SizedBox.shrink();
    }
    final tt = context.tt;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          key: const ValueKey('constellation.fieldNewRings'),
          size: Size.infinite,
          painter: ConstellationFieldNewRingPainter(
            frame: widget.frame,
            newGraphIds: widget.newGraphIds,
            dimmedGraphIds: widget.dimmedGraphIds,
            accentColor: widget.accentColor,
            gap: tt.tightGap,
            minTrustRadius: constellationTrustMinRadius(tt),
            badgeDiameter: constellationTrustBadgeDiameter(tt),
            pulse: _reduceMotion ? null : _ease,
          ),
        ),
      ),
    );
  }
}

class ConstellationFieldNewRingPainter extends CustomPainter {
  ConstellationFieldNewRingPainter({
    required this.frame,
    required this.newGraphIds,
    required this.accentColor,
    required this.gap,
    required this.minTrustRadius,
    required this.badgeDiameter,
    this.dimmedGraphIds = const {},
    this.pulse,
  }) : super(repaint: pulse);

  final ConstellationPresentationFrame frame;
  final Set<GraphNodeId> newGraphIds;
  final Set<GraphNodeId> dimmedGraphIds;
  final Color accentColor;
  final double gap;
  final double minTrustRadius;
  final double badgeDiameter;
  final Animation<double>? pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final t = pulse?.value ?? 1.0;
    final stroke = TenturaSpacing.focusRing * (1.0 + 0.35 * (1 - t));
    final alpha = 0.55 + 0.45 * t;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..strokeWidth = stroke;
    for (final id in newGraphIds) {
      final body = frame.bodies[id];
      if (body == null) {
        continue;
      }
      final fade = dimmedGraphIds.contains(id)
          ? kConstellationTrustChainDimOpacity
          : 1.0;
      paint.color = accentColor.withValues(alpha: alpha * fade);
      final g = constellationNodeRingGeometry(
        body: body,
        minTarget: kMinInteractiveDimension,
        gap: gap,
        minTrustRadius: minTrustRadius,
        badgeDiameter: badgeDiameter,
        rtl: false,
      );
      final radius = math.max(g.trustRadius, body.shortestSide / 2 + stroke);
      canvas.drawCircle(g.centre, radius, paint);
    }
  }

  @override
  bool shouldRepaint(ConstellationFieldNewRingPainter old) =>
      !identical(old.frame, frame) ||
      !setEquals(old.newGraphIds, newGraphIds) ||
      !setEquals(old.dimmedGraphIds, dimmedGraphIds) ||
      old.accentColor != accentColor ||
      old.gap != gap ||
      old.minTrustRadius != minTrustRadius ||
      old.badgeDiameter != badgeDiameter ||
      old.pulse != pulse;
}

/// Legend sample: a person with the «new on your Field» accent ring.
class ConstellationFieldNewRingSwatch extends StatelessWidget {
  const ConstellationFieldNewRingSwatch({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final size = tt.avatarSize;
    final body = Rect.fromCircle(
      center: Offset(size / 2, size / 2),
      radius: size * 0.36,
    );
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: ConstellationFieldNewRingPainter(
                frame: ConstellationPresentationFrame(
                  snapshot: 'fieldNewSwatch',
                  cameraRevision: 0,
                  detail: ConstellationDetailLevel.close,
                  paintOrder: const ['swatch'],
                  bodies: {'swatch': body},
                  labels: const {},
                  tapTargets: const {},
                  chips: const {},
                  forcedLabels: const {},
                ),
                newGraphIds: const {'swatch'},
                accentColor: scheme.secondary,
                gap: tt.tightGap,
                minTrustRadius: constellationTrustMinRadius(tt),
                badgeDiameter: constellationTrustBadgeDiameter(tt),
              ),
            ),
          ),
          Positioned.fromRect(
            rect: body,
            child: CircleAvatar(
              backgroundColor: scheme.surfaceContainerHighest,
              child: Icon(
                Icons.person_outline,
                size: body.width * 0.6,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
