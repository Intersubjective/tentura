import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/constellation_trust_badge.dart';
import '../utils/constellation_presentation_frame.dart';
import '../utils/constellation_tap_resolver.dart';

/// How a trust badge looks: a ring around the person and a glyph disc on
/// it. Colour is never the only cue: the ring's pattern and the glyph differ
/// as well (#643).
@immutable
final class ConstellationTrustBadgeStyle {
  const ConstellationTrustBadgeStyle({
    required this.color,
    required this.icon,
    required this.dash,
    required this.gap,
  });

  final Color color;
  final IconData icon;

  /// Dash and gap of the ring, in px along it; a zero dash is a solid ring.
  final double dash;
  final double gap;
}

ConstellationTrustBadgeStyle constellationTrustBadgeStyle(
  ConstellationTrustBadge badge,
  ColorScheme scheme, {
  required bool rtl,
}) {
  const stroke = TenturaSpacing.focusRing;
  return switch (badge) {
    ConstellationTrustBadge.mutual => ConstellationTrustBadgeStyle(
      color: scheme.primary,
      icon: Icons.sync_alt,
      dash: 0,
      gap: 0,
    ),
    ConstellationTrustBadge.youTrust => ConstellationTrustBadgeStyle(
      color: scheme.primary,
      icon: rtl ? Icons.arrow_back : Icons.arrow_forward,
      dash: stroke * 2,
      gap: stroke * 1.5,
    ),
    ConstellationTrustBadge.theyTrust => ConstellationTrustBadgeStyle(
      color: scheme.tertiary,
      icon: rtl ? Icons.arrow_forward : Icons.arrow_back,
      dash: stroke * 2,
      gap: stroke * 1.5,
    ),
    // A dotted ring: round caps on near-zero dashes.
    ConstellationTrustBadge.contactOnly => ConstellationTrustBadgeStyle(
      color: scheme.onSurfaceVariant,
      icon: Icons.visibility_off_outlined,
      dash: 0.01,
      gap: stroke * 2,
    ),
  };
}

String constellationTrustBadgeLabel(L10n l10n, ConstellationTrustBadge badge) =>
    switch (badge) {
      ConstellationTrustBadge.mutual => l10n.constellationTrustMutual,
      ConstellationTrustBadge.youTrust => l10n.constellationTrustYouTrust,
      ConstellationTrustBadge.theyTrust => l10n.constellationTrustTheyTrust,
      ConstellationTrustBadge.contactOnly => l10n.constellationTrustContactOnly,
    };

String constellationTrustBadgeHint(L10n l10n, ConstellationTrustBadge badge) =>
    switch (badge) {
      ConstellationTrustBadge.mutual => l10n.constellationTrustMutualHint,
      ConstellationTrustBadge.youTrust => l10n.constellationTrustYouTrustHint,
      ConstellationTrustBadge.theyTrust => l10n.constellationTrustTheyTrustHint,
      ConstellationTrustBadge.contactOnly =>
        l10n.constellationTrustContactOnlyHint,
    };

/// The ring layer's inputs for the nodes on the map: each person's trust
/// badge and the selected node, by graph id.
({
  Map<GraphNodeId, ConstellationTrustBadge> trust,
  GraphNodeId? selected,
})
constellationNodeRingInputs({
  required Map<GraphNodeId, NodeDetails> nodeByGraphId,
  required Map<String, ConstellationTrustBadge> trustByPersonId,
  required String? selectedPersonId,
  required String? selectedRequestId,
}) {
  final trust = <GraphNodeId, ConstellationTrustBadge>{};
  GraphNodeId? selected;
  for (final MapEntry(key: graphId, value: node) in nodeByGraphId.entries) {
    final (beaconId, personId) = switch (node) {
      FieldPersonNode(:final person) => (null, person.id),
      FieldBeaconNode(:final request?) => (request.id, null),
      FieldBeaconNode(:final post?) => (post.id, null),
      _ => (null, null),
    };
    if (personId != null) {
      if (trustByPersonId[personId] case final badge?) {
        trust[graphId] = badge;
      }
      if (personId == selectedPersonId) {
        selected = graphId;
      }
    } else if (beaconId != null && beaconId == selectedRequestId) {
      selected = graphId;
    }
  }
  return (trust: trust, selected: selected);
}

/// On-screen geometry of the rings around one node, in viewport px.
@immutable
final class ConstellationNodeRingGeometry {
  const ConstellationNodeRingGeometry({
    required this.centre,
    required this.trustRadius,
    required this.actionRadius,
    required this.badgeCentre,
    required this.badgeDiameter,
    required this.showsActionRing,
  });

  final Offset centre;

  /// The trust ring hugs the body; it never shrinks below a readable size.
  final double trustRadius;

  /// The hover / selection ring: at least half of `minTarget`, and outside
  /// the body and the trust ring, so it is always larger than the node
  /// (#640).
  final double actionRadius;

  final Offset badgeCentre;
  final double badgeDiameter;

  /// The node is smaller on screen than a tap target, so its hover and
  /// selection rings are drawn at the target size.
  final bool showsActionRing;
}

ConstellationNodeRingGeometry constellationNodeRingGeometry({
  required Rect body,
  required double minTarget,
  required double gap,
  required double minTrustRadius,
  required double badgeDiameter,
  required bool hasTrustRing,
  required bool rtl,
}) {
  const stroke = TenturaSpacing.focusRing;
  final bodyRadius = body.shortestSide / 2;
  final trustRadius = math.max(bodyRadius + gap + stroke / 2, minTrustRadius);
  final innerEdge = hasTrustRing ? trustRadius : bodyRadius;
  final actionRadius = math.max(minTarget / 2, innerEdge + gap + stroke);
  // Top start of the trust ring, at 45 degrees: a person's label sits
  // below it and the pin badge at the top end.
  final offset = trustRadius * math.sqrt1_2;
  return ConstellationNodeRingGeometry(
    centre: body.center,
    trustRadius: trustRadius,
    actionRadius: actionRadius,
    badgeCentre: body.center + Offset(rtl ? offset : -offset, -offset),
    badgeDiameter: badgeDiameter,
    showsActionRing: body.shortestSide < minTarget,
  );
}

/// On-screen diameter of a trust glyph disc; fixed, so it stays readable at
/// any zoom.
double constellationTrustBadgeDiameter(TenturaTokens tt) => tt.iconSize * 0.75;

/// The smallest trust ring, around a node zoomed far out.
double constellationTrustMinRadius(TenturaTokens tt) => tt.avatarTinySize / 2;

/// How far a node's decorations reach past its body at the top and sides,
/// for label and chip placement: [base] (pin / status badges) or, for a
/// person with a trust badge, its glyph disc if that reaches further, so no
/// label or chip is placed over it.
double constellationNodeBadgeOverhang({
  required double base,
  required double bodyDiameter,
  required bool hasTrustBadge,
  required TenturaTokens tt,
}) {
  if (!hasTrustBadge) {
    return base;
  }
  final body = Rect.fromCircle(center: Offset.zero, radius: bodyDiameter / 2);
  final g = constellationNodeRingGeometry(
    body: body,
    minTarget: kMinInteractiveDimension,
    gap: tt.tightGap,
    minTrustRadius: constellationTrustMinRadius(tt),
    badgeDiameter: constellationTrustBadgeDiameter(tt),
    hasTrustRing: true,
    rtl: false,
  );
  final disc = Rect.fromCircle(
    center: g.badgeCentre,
    radius: g.badgeDiameter / 2,
  );
  // The disc sits at the top start; the decorated rect grows symmetrically,
  // so the reach to the start covers either text direction.
  return math.max(
    base,
    math.max(body.top - disc.top, body.left - disc.left),
  );
}

/// Viewport-space rings drawn over the field's nodes (#640, #643):
///
/// * every person with a trust relation to the viewer gets a trust ring and
///   a glyph disc, at a fixed on-screen size, so they stay readable however
///   far the map is zoomed out;
/// * a node smaller than a tap target gets a hover ring (mouse) and, when
///   selected, a selection ring at the tap target's size — larger than the
///   node, matching what a tap there resolves to.
///
/// It paints only; pointers pass through to the map below.
class ConstellationNodeRingLayer extends StatefulWidget {
  const ConstellationNodeRingLayer({
    required this.frame,
    required this.trustByGraphId,
    required this.selectedGraphId,
    super.key,
  });

  final ConstellationPresentationFrame frame;
  final Map<GraphNodeId, ConstellationTrustBadge> trustByGraphId;
  final GraphNodeId? selectedGraphId;

  @override
  State<ConstellationNodeRingLayer> createState() =>
      _ConstellationNodeRingLayerState();
}

class _ConstellationNodeRingLayerState
    extends State<ConstellationNodeRingLayer> {
  final _hover = ValueNotifier<Offset?>(null);
  final _glyphs = ConstellationTrustGlyphCache();

  @override
  void dispose() {
    _hover.dispose();
    _glyphs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return MouseRegion(
      hitTestBehavior: HitTestBehavior.translucent,
      onHover: (event) => _hover.value = event.localPosition,
      onExit: (_) => _hover.value = null,
      child: IgnorePointer(
        child: CustomPaint(
          key: const ValueKey('constellation.nodeRings'),
          size: Size.infinite,
          painter: ConstellationNodeRingPainter(
            frame: widget.frame,
            trustByGraphId: widget.trustByGraphId,
            selectedGraphId: widget.selectedGraphId,
            hover: _hover,
            minTarget: kMinInteractiveDimension,
            gap: tt.tightGap,
            minTrustRadius: constellationTrustMinRadius(tt),
            badgeDiameter: constellationTrustBadgeDiameter(tt),
            scheme: scheme,
            textDirection: Directionality.of(context),
            rtl: rtl,
            glyphs: _glyphs,
          ),
        ),
      ),
    );
  }
}

class ConstellationNodeRingPainter extends CustomPainter {
  ConstellationNodeRingPainter({
    required this.frame,
    required this.trustByGraphId,
    required this.selectedGraphId,
    required this.hover,
    required this.minTarget,
    required this.gap,
    required this.minTrustRadius,
    required this.badgeDiameter,
    required this.scheme,
    required this.textDirection,
    required this.rtl,
    this.glyphs,
  }) : super(repaint: hover);

  final ConstellationPresentationFrame frame;
  final Map<GraphNodeId, ConstellationTrustBadge> trustByGraphId;
  final GraphNodeId? selectedGraphId;
  final ValueListenable<Offset?> hover;
  final double minTarget;
  final double gap;
  final double minTrustRadius;
  final double badgeDiameter;
  final ColorScheme scheme;
  final TextDirection textDirection;
  final bool rtl;

  /// Glyph painters kept across paints; without one, each paint lays out
  /// its own and disposes them.
  final ConstellationTrustGlyphCache? glyphs;

  /// The node the mouse is over, resolved as a tap there would be.
  @visibleForTesting
  GraphNodeId? get hoveredGraphId => switch (hover.value) {
    final point? => resolveConstellationTap(frame, point),
    null => null,
  };

  ConstellationNodeRingGeometry _geometry(Rect body, bool hasTrustRing) =>
      constellationNodeRingGeometry(
        body: body,
        minTarget: minTarget,
        gap: gap,
        minTrustRadius: minTrustRadius,
        badgeDiameter: badgeDiameter,
        hasTrustRing: hasTrustRing,
        rtl: rtl,
      );

  @override
  void paint(Canvas canvas, Size size) {
    final visible = (Offset.zero & size).inflate(minTarget);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = TenturaSpacing.focusRing
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final ownGlyphs = glyphs == null ? ConstellationTrustGlyphCache() : null;
    final glyphCache = glyphs ?? ownGlyphs!;

    for (final id in frame.paintOrder) {
      final badge = trustByGraphId[id];
      final body = frame.bodies[id];
      if (badge == null || body == null || !visible.overlaps(body)) {
        continue;
      }
      final g = _geometry(body, true);
      final style = constellationTrustBadgeStyle(badge, scheme, rtl: rtl);
      ring.color = style.color;
      if (style.dash <= 0) {
        canvas.drawCircle(g.centre, g.trustRadius, ring);
      } else {
        canvas.drawPath(
          _dashedCircle(g.centre, g.trustRadius, style.dash, style.gap),
          ring,
        );
      }
      _paintBadge(
        canvas,
        g,
        style,
        glyphCache.painterFor(
          style,
          size: badgeDiameter * 0.7,
          textDirection: textDirection,
        ),
      );
    }
    ownGlyphs?.dispose();

    final selected = selectedGraphId;
    final hovered = hoveredGraphId;
    for (final (id, color, width) in [
      if (hovered != null && hovered != selected)
        (hovered, scheme.onSurfaceVariant, TenturaSpacing.focusRing),
      if (selected != null)
        (selected, scheme.secondary, TenturaSpacing.focusRing * 1.5),
    ]) {
      final body = frame.bodies[id];
      if (body == null) {
        continue;
      }
      final g = _geometry(body, trustByGraphId.containsKey(id));
      if (!g.showsActionRing) {
        continue;
      }
      canvas.drawCircle(
        g.centre,
        g.actionRadius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = color
          ..isAntiAlias = true,
      );
    }
  }

  void _paintBadge(
    Canvas canvas,
    ConstellationNodeRingGeometry g,
    ConstellationTrustBadgeStyle style,
    TextPainter glyph,
  ) {
    final radius = g.badgeDiameter / 2;
    canvas
      ..drawCircle(g.badgeCentre, radius, Paint()..color = scheme.surface)
      ..drawCircle(
        g.badgeCentre,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = style.color,
      );
    glyph.paint(
      canvas,
      g.badgeCentre - Offset(glyph.width / 2, glyph.height / 2),
    );
  }

  static Path _dashedCircle(
    Offset centre,
    double radius,
    double dash,
    double gap,
  ) {
    final count = math.max(4, (2 * math.pi * radius / (dash + gap)).floor());
    final step = 2 * math.pi / count;
    final sweep = step * dash / (dash + gap);
    final rect = Rect.fromCircle(center: centre, radius: radius);
    final path = Path();
    for (var i = 0; i < count; i++) {
      path.addArc(rect, -math.pi / 2 + i * step, sweep);
    }
    return path;
  }

  @override
  bool shouldRepaint(ConstellationNodeRingPainter old) =>
      !identical(old.frame, frame) ||
      !mapEquals(old.trustByGraphId, trustByGraphId) ||
      old.selectedGraphId != selectedGraphId ||
      old.hover != hover ||
      old.minTarget != minTarget ||
      old.gap != gap ||
      old.minTrustRadius != minTrustRadius ||
      old.badgeDiameter != badgeDiameter ||
      old.scheme != scheme ||
      old.rtl != rtl;
}

/// Laid-out glyph painters by icon, colour, size and direction; rebuilt only
/// when one of them changes, so a pan or a hover lays out no text.
final class ConstellationTrustGlyphCache {
  final _painters = <(IconData, Color, double, TextDirection), TextPainter>{};

  TextPainter painterFor(
    ConstellationTrustBadgeStyle style, {
    required double size,
    required TextDirection textDirection,
  }) => _painters.putIfAbsent(
    (style.icon, style.color, size, textDirection),
    () => TextPainter(
      text: TextSpan(
        text: String.fromCharCode(style.icon.codePoint),
        style: TextStyle(
          fontFamily: style.icon.fontFamily,
          package: style.icon.fontPackage,
          fontSize: size,
          height: 1,
          color: style.color,
        ),
      ),
      textDirection: textDirection,
    )..layout(),
  );

  void dispose() {
    for (final painter in _painters.values) {
      painter.dispose();
    }
    _painters.clear();
  }
}

/// Legend sample of a trust badge: a person disc with its ring and glyph.
class ConstellationTrustBadgeSwatch extends StatelessWidget {
  const ConstellationTrustBadgeSwatch({required this.badge, super.key});

  final ConstellationTrustBadge badge;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final size = tt.avatarSize;
    final body = Rect.fromCircle(
      center: Offset(size / 2, size / 2),
      radius: size / 2 - tt.iconSize * 0.4,
    );
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
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
          Positioned.fill(
            child: CustomPaint(
              painter: ConstellationNodeRingPainter(
                frame: ConstellationPresentationFrame(
                  snapshot: badge,
                  cameraRevision: 0,
                  detail: ConstellationDetailLevel.normal,
                  paintOrder: const ['swatch'],
                  bodies: {'swatch': body},
                  labels: const {},
                  tapTargets: const {},
                  chips: const {},
                  forcedLabels: const {},
                ),
                trustByGraphId: {'swatch': badge},
                selectedGraphId: null,
                hover: _noHover,
                minTarget: kMinInteractiveDimension,
                gap: tt.tightGap,
                minTrustRadius: constellationTrustMinRadius(tt),
                badgeDiameter: constellationTrustBadgeDiameter(tt),
                scheme: scheme,
                textDirection: Directionality.of(context),
                rtl: Directionality.of(context) == TextDirection.rtl,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

final ValueListenable<Offset?> _noHover = ValueNotifier<Offset?>(null);
