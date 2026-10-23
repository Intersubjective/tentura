import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

import '../bloc/constellation_presence_cubit.dart';
import '../utils/constellation_presentation_frame.dart';
import 'constellation_node_ring_layer.dart';

/// Halo band width as a share of the body radius: the halo scales with the
/// node, so a zoomed-out node is never covered by a fixed-size mark.
const kConstellationPresenceHaloWidthRatio = 0.25;

/// Clearance between the node (or its trust ring) and the halo, as a share
/// of the body radius.
const kConstellationPresenceHaloGapRatio = 0.08;

/// The narrowest halo band, in px: at bare zoom the halo is how an online
/// person is spotted, so it never thins below this.
const kConstellationPresenceHaloMinWidth = TenturaSpacing.focusRing * 2;

/// The smallest clearance, in px.
const kConstellationPresenceHaloMinGap = TenturaSpacing.tight / 2;

/// One breath in or out; a full pulse is twice this.
const kConstellationPresencePulseHalfPeriod = Duration(milliseconds: 1200);

/// On-screen geometry of one person's presence halo, in viewport px: a band
/// from [innerRadius] out to [outerRadius], always outside the body.
@immutable
final class ConstellationPresenceHaloGeometry {
  const ConstellationPresenceHaloGeometry({
    required this.centre,
    required this.innerRadius,
    required this.width,
  });

  final Offset centre;
  final double innerRadius;
  final double width;

  double get outerRadius => innerRadius + width;
}

/// The halo around [body]: just outside it, or outside its trust ring of
/// [trustRadius] (stroke centre) when that ring is drawn.
ConstellationPresenceHaloGeometry constellationPresenceHaloGeometry({
  required Rect body,
  double? trustRadius,
}) {
  final bodyRadius = body.shortestSide / 2;
  final innerEdge = trustRadius == null
      ? bodyRadius
      : math.max(bodyRadius, trustRadius + TenturaSpacing.focusRing / 2);
  final gap = math.max(
    bodyRadius * kConstellationPresenceHaloGapRatio,
    kConstellationPresenceHaloMinGap,
  );
  return ConstellationPresenceHaloGeometry(
    centre: body.center,
    innerRadius: innerEdge + gap,
    width: math.max(
      bodyRadius * kConstellationPresenceHaloWidthRatio,
      kConstellationPresenceHaloMinWidth,
    ),
  );
}

/// The halo of node [id] on [frame], or null when it has no body there:
/// outside its trust ring when that ring is drawn (normal detail, a person
/// in [trustGraphIds]), else just outside the body.
ConstellationPresenceHaloGeometry? constellationPresenceHaloOf({
  required ConstellationPresentationFrame frame,
  required GraphNodeId id,
  required Set<GraphNodeId> trustGraphIds,
  required double trustGap,
  required double minTrustRadius,
}) {
  final body = frame.bodies[id];
  if (body == null) {
    return null;
  }
  // Trust rings show only at normal detail (as the ring layer draws them).
  final ringed =
      frame.detail == ConstellationDetailLevel.normal &&
      trustGraphIds.contains(id);
  return constellationPresenceHaloGeometry(
    body: body,
    trustRadius: ringed
        ? constellationNodeRingGeometry(
            body: body,
            minTarget: 0,
            gap: trustGap,
            minTrustRadius: minTrustRadius,
            badgeDiameter: 0,
            hasTrustRing: true,
            rtl: false,
          ).trustRadius
        : null,
  );
}

/// Whether [g] reaches into [viewport] (both in viewport px).
bool constellationPresenceHaloVisible(
  ConstellationPresenceHaloGeometry g,
  Rect viewport,
) => viewport.overlaps(
  Rect.fromCircle(center: g.centre, radius: g.outerRadius),
);

/// The graph ids of the people in [onlinePersonIds] that are on the map:
/// person nodes are `fp:<id>`, and [isOnMap] tells which are drawn.
Set<GraphNodeId> constellationOnlineGraphIds({
  required Set<String> onlinePersonIds,
  required bool Function(GraphNodeId id) isOnMap,
}) => {
  for (final personId in onlinePersonIds)
    if ('fp:$personId' case final graphId when isOnMap(graphId)) graphId,
};

/// Viewport-space presence halos under the field's rings: a soft band in
/// the positive colour around every online person, breathing slowly.
///
/// One controller drives every halo, and only this layer repaints on its
/// ticks: the halos sit in their own repaint boundary, apart from the trust
/// rings and the labels, and the graph is never rebuilt. The pulse runs only
/// while an online person is on screen and the field's tickers are on
/// ([TickerMode]); with reduced motion the halo is drawn still.
class ConstellationPresenceHaloLayer extends StatefulWidget {
  const ConstellationPresenceHaloLayer({
    required this.frame,
    required this.onlineGraphIds,
    required this.trustGraphIds,
    required this.viewport,
    super.key,
  });

  final ConstellationPresentationFrame frame;
  final Set<GraphNodeId> onlineGraphIds;

  /// People drawn with a trust ring (at normal detail): their halo goes
  /// outside it.
  final Set<GraphNodeId> trustGraphIds;
  final Size viewport;

  @override
  State<ConstellationPresenceHaloLayer> createState() =>
      _ConstellationPresenceHaloLayerState();
}

class _ConstellationPresenceHaloLayerState
    extends State<ConstellationPresenceHaloLayer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: kConstellationPresencePulseHalfPeriod,
  );
  late final Animation<double> _breath = CurvedAnimation(
    parent: _pulse,
    curve: Curves.easeInOut,
  );
  bool _reduceMotion = false;
  double _trustGap = 0;
  double _minTrustRadius = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    final tt = context.tt;
    _trustGap = tt.tightGap;
    _minTrustRadius = constellationTrustMinRadius(tt);
    _syncTicker();
  }

  /// Whether a halo would be painted on the viewport now.
  bool _anyHaloOnScreen() {
    final viewport = Offset.zero & widget.viewport;
    if (viewport.isEmpty) {
      return false;
    }
    for (final id in widget.onlineGraphIds) {
      final g = constellationPresenceHaloOf(
        frame: widget.frame,
        id: id,
        trustGraphIds: widget.trustGraphIds,
        trustGap: _trustGap,
        minTrustRadius: _minTrustRadius,
      );
      if (g != null && constellationPresenceHaloVisible(g, viewport)) {
        return true;
      }
    }
    return false;
  }

  @override
  void didUpdateWidget(ConstellationPresenceHaloLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    final run = !_reduceMotion && _anyHaloOnScreen();
    if (run && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!run && _pulse.isAnimating) {
      _pulse.stop();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onlineGraphIds.isEmpty) {
      return const SizedBox.shrink();
    }
    final tt = context.tt;
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          key: const ValueKey('constellation.presenceHalos'),
          size: Size.infinite,
          painter: ConstellationPresenceHaloPainter(
            frame: widget.frame,
            onlineGraphIds: widget.onlineGraphIds,
            trustGraphIds: widget.trustGraphIds,
            color: tt.good,
            trustGap: _trustGap,
            minTrustRadius: _minTrustRadius,
            pulse: _reduceMotion ? null : _breath,
          ),
        ),
      ),
    );
  }
}

/// Paints the presence halos of [onlineGraphIds]. With a [pulse] (0..1) the
/// band breathes: its inner edge stays put while its core thickens and
/// brightens and a faint outer glow swells; without one it is drawn still,
/// fully out.
class ConstellationPresenceHaloPainter extends CustomPainter {
  ConstellationPresenceHaloPainter({
    required this.frame,
    required this.onlineGraphIds,
    required this.trustGraphIds,
    required this.color,
    required this.trustGap,
    required this.minTrustRadius,
    this.pulse,
  }) : super(repaint: pulse);

  final ConstellationPresentationFrame frame;
  final Set<GraphNodeId> onlineGraphIds;
  final Set<GraphNodeId> trustGraphIds;
  final Color color;
  final double trustGap;
  final double minTrustRadius;
  final Animation<double>? pulse;

  /// The halo of the node [id] at this frame, or null when it has none.
  @visibleForTesting
  ConstellationPresenceHaloGeometry? geometryOf(GraphNodeId id) =>
      onlineGraphIds.contains(id)
      ? constellationPresenceHaloOf(
          frame: frame,
          id: id,
          trustGraphIds: trustGraphIds,
          trustGap: trustGap,
          minTrustRadius: minTrustRadius,
        )
      : null;

  @override
  void paint(Canvas canvas, Size size) {
    final t = pulse?.value ?? 1.0;
    final viewport = Offset.zero & size;
    final core = Paint()
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..color = color.withValues(alpha: 0.5 + 0.4 * t);
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true
      ..color = color.withValues(alpha: 0.12 + 0.18 * t);
    for (final id in onlineGraphIds) {
      final g = geometryOf(id);
      if (g == null || !constellationPresenceHaloVisible(g, viewport)) {
        continue;
      }
      // Core: 40-60 % of the band from the inner edge; glow: the rest of the
      // band out to 60-100 %.
      final coreWidth = g.width * (0.4 + 0.2 * t);
      final glowWidth = g.width * (0.2 + 0.2 * t);
      core.strokeWidth = coreWidth;
      glow.strokeWidth = glowWidth;
      canvas
        ..drawCircle(g.centre, g.innerRadius + coreWidth / 2, core)
        ..drawCircle(
          g.centre,
          g.innerRadius + coreWidth + glowWidth / 2,
          glow,
        );
    }
  }

  @override
  bool shouldRepaint(ConstellationPresenceHaloPainter old) =>
      !identical(old.frame, frame) ||
      !setEquals(old.onlineGraphIds, onlineGraphIds) ||
      !setEquals(old.trustGraphIds, trustGraphIds) ||
      old.color != color ||
      old.trustGap != trustGap ||
      old.minTrustRadius != minTrustRadius ||
      old.pulse != pulse;
}

/// Rebuilds [builder] with whether [personId] is online on the field. Off
/// the field's presence scope (no [ConstellationPresenceCubit] above) it is
/// always offline.
class ConstellationPersonPresenceBuilder extends StatelessWidget {
  const ConstellationPersonPresenceBuilder({
    required this.personId,
    required this.builder,
    super.key,
  });

  final String? personId;
  final Widget Function(BuildContext context, bool online) builder;

  @override
  Widget build(BuildContext context) {
    final id = personId;
    final presence = context.read<ConstellationPresenceCubit?>();
    if (id == null || presence == null) {
      return builder(context, false);
    }
    return BlocSelector<ConstellationPresenceCubit, Set<String>, bool>(
      bloc: presence,
      selector: (online) => online.contains(id),
      builder: builder,
    );
  }
}

/// Legend sample of the presence halo: a person disc with a still halo.
class ConstellationPresenceHaloSwatch extends StatelessWidget {
  const ConstellationPresenceHaloSwatch({super.key});

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
              painter: ConstellationPresenceHaloPainter(
                frame: ConstellationPresentationFrame(
                  snapshot: 'presenceSwatch',
                  cameraRevision: 0,
                  detail: ConstellationDetailLevel.normal,
                  paintOrder: const ['swatch'],
                  bodies: {'swatch': body},
                  labels: const {},
                  tapTargets: const {},
                  chips: const {},
                  forcedLabels: const {},
                ),
                onlineGraphIds: const {'swatch'},
                trustGraphIds: const {},
                color: tt.good,
                trustGap: tt.tightGap,
                minTrustRadius: constellationTrustMinRadius(tt),
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
