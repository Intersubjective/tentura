import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/constellation_trust_badge.dart';
import '../../domain/constellation_trust_chain.dart';
import '../utils/constellation_presentation_frame.dart';
import '../utils/constellation_tap_resolver.dart';

/// How a trust badge looks: a glyph disc on the person's top start corner.
/// Colour is never the only cue: the glyph differs as well (#643).
@immutable
final class ConstellationTrustBadgeStyle {
  const ConstellationTrustBadgeStyle({
    required this.color,
    required this.icon,
  });

  final Color color;
  final IconData icon;
}

ConstellationTrustBadgeStyle constellationTrustBadgeStyle(
  ConstellationTrustBadge badge,
  ColorScheme scheme, {
  required bool rtl,
}) {
  return switch (badge) {
    ConstellationTrustBadge.mutual => ConstellationTrustBadgeStyle(
      color: scheme.primary,
      icon: Icons.sync_alt,
    ),
    ConstellationTrustBadge.youTrust => ConstellationTrustBadgeStyle(
      color: scheme.primary,
      icon: rtl ? Icons.arrow_back : Icons.arrow_forward,
    ),
    ConstellationTrustBadge.theyTrust => ConstellationTrustBadgeStyle(
      color: scheme.tertiary,
      icon: rtl ? Icons.arrow_forward : Icons.arrow_back,
    ),
    ConstellationTrustBadge.contactOnly => ConstellationTrustBadgeStyle(
      color: scheme.onSurfaceVariant,
      icon: Icons.visibility_off_outlined,
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

/// On-screen geometry of the marks around one node, in viewport px.
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

  /// The circle the trust glyph disc is centred on: it hugs the body and
  /// never shrinks below a readable size.
  final double trustRadius;

  /// The hover / selection ring: at least half of `minTarget`, and outside
  /// the body, so it is always larger than the node (#640).
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
  required bool rtl,
}) {
  const stroke = TenturaSpacing.focusRing;
  final bodyRadius = body.shortestSide / 2;
  final trustRadius = math.max(bodyRadius + gap + stroke / 2, minTrustRadius);
  final actionRadius = math.max(minTarget / 2, bodyRadius + gap + stroke);
  // Top start, at 45 degrees: a person's label sits below and the pin badge
  // at the top end.
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

/// The smallest circle a trust glyph disc sits on, around a small node.
double constellationTrustMinRadius(TenturaTokens tt) => tt.avatarTinySize / 2;

/// Zoomed out (overview / bare detail) the glyph disc gives way to a rim on
/// the node's own edge. Its width scales with the node, so it never covers
/// it; its colour is a muted tone of the badge colour.
typedef ConstellationTrustRim = ({Color color, double width});

/// The rim for [badge] around [body], or null for a contact without
/// content (no relation colour to show). Mutual trust gets the full width,
/// one-way trust a thinner rim; «they trust you» keeps its own colour.
ConstellationTrustRim? constellationTrustRimOf(
  ConstellationTrustBadge badge,
  Rect body,
  ColorScheme scheme,
) {
  final full = (body.shortestSide / 2 * 0.16).clamp(1, 3).toDouble();
  final (width, base) = switch (badge) {
    ConstellationTrustBadge.mutual => (full, scheme.primary),
    ConstellationTrustBadge.youTrust => (
      math.max<double>(1, full * 0.6),
      scheme.primary,
    ),
    ConstellationTrustBadge.theyTrust => (
      math.max<double>(1, full * 0.6),
      scheme.tertiary,
    ),
    ConstellationTrustBadge.contactOnly => (0.0, null),
  };
  if (base == null) {
    return null;
  }
  return (
    color: constellationMutedRimColor(base, scheme.surface),
    width: width,
  );
}

/// Contrast a rim keeps against the field (WCAG 1.4.11, graphical objects).
const kConstellationTrustRimMinContrast = 3.0;

final _mutedRimColors = <(Color, Color), Color>{};

/// [base] desaturated, then darkened on a light [background] or lightened
/// on a dark one until it keeps [kConstellationTrustRimMinContrast]
/// against it: muted, yet readable in both themes.
Color constellationMutedRimColor(Color base, Color background) =>
    _mutedRimColors[(base, background)] ??= () {
      final bg = background.computeLuminance();
      final light = bg > 0.5;
      var hsl = HSLColor.fromColor(base);
      hsl = hsl.withSaturation(hsl.saturation * 0.55);
      double contrast(Color c) {
        final l = c.computeLuminance();
        final (hi, lo) = l > bg ? (l, bg) : (bg, l);
        return (hi + 0.05) / (lo + 0.05);
      }

      for (var i = 0; i < 40; i++) {
        if (contrast(hsl.toColor()) >= kConstellationTrustRimMinContrast) {
          break;
        }
        final next = (hsl.lightness + (light ? -0.025 : 0.025))
            .clamp(0, 1)
            .toDouble();
        if (next == hsl.lightness) {
          break;
        }
        hsl = hsl.withLightness(next);
      }
      return hsl.toColor();
    }();

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
/// * every person with a trust relation to the viewer gets a glyph disc on
///   their top start corner, at a fixed on-screen size, at normal detail (as
///   the pin badge); zoomed out, where the disc would cover the node, a
///   muted rim on the node's own edge instead (no rim for a contact without
///   content). There is no ring around the person: it repeated the disc and
///   cluttered a busy field;
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
    this.dimmedGraphIds = const {},
    this.hiddenLabelOf,
    super.key,
  });

  final ConstellationPresentationFrame frame;
  final Map<GraphNodeId, ConstellationTrustBadge> trustByGraphId;
  final GraphNodeId? selectedGraphId;

  /// The name of a node, drawn while a mouse is over a node that has no
  /// placed label (#459); touch never shows it.
  final String? Function(GraphNodeId id)? hiddenLabelOf;

  /// Nodes off the selected person's trust chain (#641): their trust marks
  /// fade with them.
  final Set<GraphNodeId> dimmedGraphIds;

  @override
  State<ConstellationNodeRingLayer> createState() =>
      _ConstellationNodeRingLayerState();
}

class _ConstellationNodeRingLayerState
    extends State<ConstellationNodeRingLayer> {
  final _hover = ValueNotifier<Offset?>(null);
  final _glyphs = ConstellationTrustGlyphCache();
  GraphNodeId? _mouseOver;

  void _onHover(PointerHoverEvent event) {
    _hover.value = event.localPosition;
    final id = event.kind == PointerDeviceKind.mouse
        ? resolveConstellationTap(widget.frame, event.localPosition)
        : null;
    if (id != _mouseOver) {
      setState(() => _mouseOver = id);
    }
  }

  void _onExit() {
    _hover.value = null;
    if (_mouseOver != null) {
      setState(() => _mouseOver = null);
    }
  }

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
      onHover: _onHover,
      onExit: (_) => _onExit(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          IgnorePointer(
            child: CustomPaint(
              key: const ValueKey('constellation.nodeRings'),
              size: Size.infinite,
              painter: ConstellationNodeRingPainter(
                frame: widget.frame,
                trustByGraphId: widget.trustByGraphId,
                selectedGraphId: widget.selectedGraphId,
                dimmedGraphIds: widget.dimmedGraphIds,
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
          ?_hiddenLabel(tt, scheme),
        ],
      ),
    );
  }

  Widget? _hiddenLabel(TenturaTokens tt, ColorScheme scheme) {
    final id = _mouseOver;
    final body = id == null ? null : widget.frame.bodies[id];
    final text = id == null ? null : widget.hiddenLabelOf?.call(id);
    if (body == null ||
        text == null ||
        text.isEmpty ||
        widget.frame.labels.containsKey(id)) {
      return null;
    }
    final width = tt.graphLabelMaxWidthRequest;
    return Positioned(
      key: ValueKey('constellation.hoverLabel.$id'),
      left: body.center.dx - width / 2,
      top: body.bottom + tt.tightGap,
      width: width,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(tt.buttonRadius),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Padding(
            padding: EdgeInsets.all(tt.tightGap),
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TenturaText.labelSmall(scheme.onSurface),
              textAlign: TextAlign.center,
            ),
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
    this.dimmedGraphIds = const {},
    this.glyphs,
  }) : super(repaint: hover);

  final ConstellationPresentationFrame frame;
  final Map<GraphNodeId, ConstellationTrustBadge> trustByGraphId;
  final GraphNodeId? selectedGraphId;
  final Set<GraphNodeId> dimmedGraphIds;
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

  ConstellationNodeRingGeometry _geometry(Rect body) =>
      constellationNodeRingGeometry(
        body: body,
        minTarget: minTarget,
        gap: gap,
        minTrustRadius: minTrustRadius,
        badgeDiameter: badgeDiameter,
        rtl: rtl,
      );

  void _paintTrustMark(
    Canvas canvas,
    ConstellationTrustGlyphCache glyphCache,
    ConstellationTrustBadge badge,
    Rect body,
  ) {
    if (frame.detail != ConstellationDetailLevel.close) {
      // Zoomed out the fixed-size disc would cover the node: a muted rim on
      // the node's own edge, scaling with it, says the same quietly.
      if (constellationTrustRimOf(badge, body, scheme) case final rim?) {
        canvas.drawCircle(
          body.center,
          body.shortestSide / 2 - rim.width / 2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = rim.width
            ..isAntiAlias = true
            ..color = rim.color,
        );
      }
      return;
    }
    final g = _geometry(body);
    final style = constellationTrustBadgeStyle(badge, scheme, rtl: rtl);
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

  @override
  void paint(Canvas canvas, Size size) {
    final visible = (Offset.zero & size).inflate(minTarget);
    final ownGlyphs = glyphs == null ? ConstellationTrustGlyphCache() : null;
    final glyphCache = glyphs ?? ownGlyphs!;
    // Marks off the trust chain go through one translucent layer, so the
    // glyph disc fades as a whole.
    final shown = [
      for (final id in frame.paintOrder)
        if (trustByGraphId[id] case final badge?)
          if (frame.bodies[id] case final body? when visible.overlaps(body))
            (id, badge, body),
    ];
    final faded = shown.where((e) => dimmedGraphIds.contains(e.$1)).toList();
    final full = faded.isEmpty
        ? shown
        : shown.where((e) => !dimmedGraphIds.contains(e.$1)).toList();
    for (final (pass, isFaded) in [(full, false), (faded, true)]) {
      if (pass.isEmpty) {
        continue;
      }
      if (isFaded) {
        canvas.saveLayer(
          null,
          Paint()
            ..color = const Color.fromRGBO(
              0,
              0,
              0,
              kConstellationTrustChainDimOpacity,
            ),
        );
      }
      for (final (_, badge, body) in pass) {
        _paintTrustMark(canvas, glyphCache, badge, body);
      }
      if (isFaded) {
        canvas.restore();
      }
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
      final g = _geometry(body);
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

  @override
  bool shouldRepaint(ConstellationNodeRingPainter old) =>
      !identical(old.frame, frame) ||
      !mapEquals(old.trustByGraphId, trustByGraphId) ||
      old.selectedGraphId != selectedGraphId ||
      !setEquals(old.dimmedGraphIds, dimmedGraphIds) ||
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

/// Legend sample of a trust badge: a person disc with its glyph disc.
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
                  detail: ConstellationDetailLevel.close,
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
