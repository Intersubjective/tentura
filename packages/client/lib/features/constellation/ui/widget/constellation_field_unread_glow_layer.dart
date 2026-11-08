import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

import 'package:tentura/features/people_tags/domain/use_case/people_tags_case.dart';

import '../../domain/constellation_trust_chain.dart';
import '../utils/constellation_presentation_frame.dart';

/// Brief brighten when unread glow first appears (#256 xdle.3).
const kConstellationFieldUnreadPulseDuration = Duration(milliseconds: 350);

/// Fade out when unread clears (#256 xdle.3).
const kConstellationFieldUnreadFadeDuration = Duration(milliseconds: 300);

/// Baked radial sprite diameter in px (no per-node [MaskFilter.blur]).
const kConstellationFieldUnreadGlowSpriteSize = 128.0;

/// Resolves glow tint: the author's first own-tag accent, else [TenturaTokens.attentionHighlight].
Color constellationFieldUnreadGlowColor({
  required PeopleTagsCase? tags,
  required String authorId,
  required TenturaTokens tt,
  required TenturaTagColors tagColors,
}) {
  final tagCase = tags;
  if (tagCase != null) {
    final ownIds = tagCase.tagsOfPerson(authorId);
    if (ownIds.isNotEmpty) {
      for (final tag in tagCase.tags) {
        if (ownIds.contains(tag.id)) {
          return tagColors.swatchFor(tag.color).accent;
        }
      }
    }
  }
  return tt.attentionHighlight;
}

/// Shared white radial sprite, tinted at draw time: additive on dark, [BlendMode.srcIn]
/// on light (#1191 — black sprites read as a gloomy halo on near-white backgrounds).
class ConstellationFieldUnreadGlowAtlas {
  ConstellationFieldUnreadGlowAtlas._(this._sprite);

  final ui.Image _sprite;

  ui.Image imageFor({required bool isDark}) => _sprite;

  static ConstellationFieldUnreadGlowAtlas? _instance;

  static ConstellationFieldUnreadGlowAtlas get instance {
    return _instance ??= ConstellationFieldUnreadGlowAtlas._(
      _buildRadialSprite(center: const Color(0xFFFFFFFF), midAlpha: 0.38),
    );
  }

  @visibleForTesting
  static void resetForTest() {
    _instance?._sprite.dispose();
    _instance = null;
  }

  static ui.Image _buildRadialSprite({
    required Color center,
    required double midAlpha,
  }) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const size = kConstellationFieldUnreadGlowSpriteSize;
    const rect = Rect.fromLTWH(0, 0, size, size);
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          center,
          center.withValues(alpha: midAlpha),
          center.withValues(alpha: 0),
        ],
        stops: const [0, 0.42, 1],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
    return recorder.endRecording().toImageSync(size.toInt(), size.toInt());
  }
}

/// Viewport-space ambient glow under unread Requests and Posts (#256 xdle.3).
class ConstellationFieldUnreadGlowLayer extends StatefulWidget {
  const ConstellationFieldUnreadGlowLayer({
    required this.frame,
    required this.glowByGraphId,
    required this.colorForAuthor,
    this.dimmedGraphIds = const {},
    super.key,
  });

  final ConstellationPresentationFrame frame;

  /// Graph id (`fr:` or rolled-up `fp:`) → author id for tint lookup.
  final Map<String, String> glowByGraphId;
  final Color Function(String authorId) colorForAuthor;
  final Set<GraphNodeId> dimmedGraphIds;

  @override
  State<ConstellationFieldUnreadGlowLayer> createState() =>
      _ConstellationFieldUnreadGlowLayerState();
}

class _ConstellationFieldUnreadGlowLayerState
    extends State<ConstellationFieldUnreadGlowLayer>
    with TickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: kConstellationFieldUnreadPulseDuration,
  );
  late final Animation<double> _pulseEase = CurvedAnimation(
    parent: _pulse,
    curve: Curves.easeOut,
  );
  final _fadeControllers = <GraphNodeId, AnimationController>{};
  final _fadeAuthorByGraphId = <GraphNodeId, String>{};
  Set<GraphNodeId> _previousActive = const {};
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _previousActive = widget.glowByGraphId.keys.toSet();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(ConstellationFieldUnreadGlowLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final active = widget.glowByGraphId.keys.toSet();
    final added = active.difference(_previousActive);
    final removed = _previousActive.difference(active);

    for (final id in removed) {
      final authorId =
          widget.glowByGraphId[id] ?? oldWidget.glowByGraphId[id] ?? '';
      if (authorId.isEmpty) {
        continue;
      }
      _fadeAuthorByGraphId[id] = authorId;
      final controller =
          AnimationController(
            vsync: this,
            duration: kConstellationFieldUnreadFadeDuration,
          )..addStatusListener((status) {
            if (status == AnimationStatus.dismissed) {
              setState(() {
                _fadeControllers.remove(id)?.dispose();
                _fadeAuthorByGraphId.remove(id);
              });
            }
          });
      _fadeControllers[id] = controller;
      if (_reduceMotion) {
        controller.value = 0;
      } else {
        controller.reverse(from: 1);
      }
    }

    for (final id in added) {
      _fadeControllers.remove(id)?.dispose();
      _fadeAuthorByGraphId.remove(id);
    }

    if (!_reduceMotion && added.isNotEmpty && !_pulse.isAnimating) {
      _pulse.forward(from: 0);
    }

    _previousActive = active;
  }

  @override
  void dispose() {
    _pulse.dispose();
    for (final c in _fadeControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, ({String authorId, double opacity})> _effectiveGlow() {
    final out = <String, ({String authorId, double opacity})>{
      for (final e in widget.glowByGraphId.entries)
        e.key: (authorId: e.value, opacity: 1),
    };
    for (final e in _fadeControllers.entries) {
      final authorId = _fadeAuthorByGraphId[e.key];
      if (authorId == null) {
        continue;
      }
      out[e.key] = (authorId: authorId, opacity: e.value.value);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final effective = _effectiveGlow();
    if (effective.isEmpty) {
      return const SizedBox.shrink();
    }
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final isDark = scheme.brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final pulseBoost = _reduceMotion
        ? 1.0
        : 1.0 + 0.35 * (1 - _pulseEase.value);
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          key: const ValueKey('constellation.fieldUnreadGlow'),
          size: Size.infinite,
          painter: ConstellationFieldUnreadGlowPainter(
            frame: widget.frame,
            glowSites: effective,
            colorForAuthor: widget.colorForAuthor,
            dimmedGraphIds: widget.dimmedGraphIds,
            atlas: ConstellationFieldUnreadGlowAtlas.instance,
            spread: tt.fieldUnreadGlowSpread,
            alphaDark: tt.fieldUnreadGlowAlphaDark,
            alphaLight: tt.fieldUnreadGlowAlphaLight,
            unreadDotSize: tt.unreadDotSize,
            unreadDotColor: tt.info,
            isDark: isDark,
            highContrast: highContrast,
            pulseBoost: pulseBoost,
            pulse: _reduceMotion ? null : _pulseEase,
            fadeControllers: _fadeControllers,
          ),
        ),
      ),
    );
  }
}

class ConstellationFieldUnreadGlowPainter extends CustomPainter {
  ConstellationFieldUnreadGlowPainter({
    required this.frame,
    required this.glowSites,
    required this.colorForAuthor,
    required this.atlas,
    required this.spread,
    required this.alphaDark,
    required this.alphaLight,
    required this.unreadDotSize,
    required this.unreadDotColor,
    required this.isDark,
    required this.highContrast,
    required this.pulseBoost,
    this.dimmedGraphIds = const {},
    this.pulse,
    this.fadeControllers = const {},
  }) : super(
         repaint: Listenable.merge([
           ?pulse,
           ...fadeControllers.values,
         ]),
       );

  final ConstellationPresentationFrame frame;
  final Map<String, ({String authorId, double opacity})> glowSites;
  final Color Function(String authorId) colorForAuthor;
  final ConstellationFieldUnreadGlowAtlas atlas;
  final double spread;
  final double alphaDark;
  final double alphaLight;
  final double unreadDotSize;
  final Color unreadDotColor;
  final bool isDark;
  final bool highContrast;
  final double pulseBoost;
  final Set<GraphNodeId> dimmedGraphIds;
  final Animation<double>? pulse;
  final Map<GraphNodeId, AnimationController> fadeControllers;

  @override
  void paint(Canvas canvas, Size size) {
    if (highContrast) {
      _paintHighContrastDots(canvas);
      return;
    }
    const src = Rect.fromLTWH(
      0,
      0,
      kConstellationFieldUnreadGlowSpriteSize,
      kConstellationFieldUnreadGlowSpriteSize,
    );
    final sprite = atlas.imageFor(isDark: isDark);
    final baseAlpha = isDark ? alphaDark : alphaLight;
    for (final entry in glowSites.entries) {
      final body = frame.bodies[entry.key];
      if (body == null || entry.value.opacity <= 0) {
        continue;
      }
      final fade = dimmedGraphIds.contains(entry.key)
          ? kConstellationTrustChainDimOpacity
          : 1.0;
      final radius = body.shortestSide / 2 * spread;
      final dst = Rect.fromCircle(center: body.center, radius: radius);
      final color = colorForAuthor(entry.value.authorId);
      final alpha = baseAlpha * entry.value.opacity * pulseBoost * fade;
      final paint = Paint()
        ..isAntiAlias = true
        ..filterQuality = FilterQuality.medium;
      if (isDark) {
        paint
          ..color = color.withValues(alpha: alpha)
          ..blendMode = BlendMode.plus;
      } else {
        paint.colorFilter = ColorFilter.mode(
          color.withValues(alpha: alpha),
          BlendMode.srcIn,
        );
      }
      canvas.drawImageRect(sprite, src, dst, paint);
    }
  }

  void _paintHighContrastDots(Canvas canvas) {
    final dotR = unreadDotSize / 2;
    final paint = Paint()
      ..color = unreadDotColor
      ..isAntiAlias = true;
    for (final entry in glowSites.entries) {
      final body = frame.bodies[entry.key];
      if (body == null || entry.value.opacity <= 0) {
        continue;
      }
      final fade = dimmedGraphIds.contains(entry.key)
          ? kConstellationTrustChainDimOpacity
          : 1.0;
      final inset = math.max(_dotInset, dotR);
      final centre = body.topRight + Offset(-inset, inset);
      paint.color = unreadDotColor.withValues(
        alpha: fade * entry.value.opacity,
      );
      canvas.drawCircle(centre, dotR, paint);
    }
  }

  static const _dotInset = 3.0;

  @override
  bool shouldRepaint(ConstellationFieldUnreadGlowPainter old) =>
      !identical(old.frame, frame) ||
      !mapEquals(old.glowSites, glowSites) ||
      old.spread != spread ||
      old.alphaDark != alphaDark ||
      old.alphaLight != alphaLight ||
      old.isDark != isDark ||
      old.highContrast != highContrast ||
      old.pulseBoost != pulseBoost ||
      !setEquals(old.dimmedGraphIds, dimmedGraphIds) ||
      old.pulse != pulse ||
      !mapEquals(old.fadeControllers, fadeControllers);
}

/// Legend sample: soft glow under a Request/Post marker.
class ConstellationFieldUnreadGlowSwatch extends StatelessWidget {
  const ConstellationFieldUnreadGlowSwatch({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final size = tt.avatarSize;
    final body = Rect.fromCircle(
      center: Offset(size / 2, size / 2),
      radius: size * 0.22,
    );
    final frame = ConstellationPresentationFrame(
      snapshot: 'unreadGlowSwatch',
      cameraRevision: 0,
      detail: ConstellationDetailLevel.close,
      paintOrder: const ['swatch'],
      bodies: {'swatch': body},
      labels: const {},
      tapTargets: const {},
      chips: const {},
      forcedLabels: const {},
    );
    return SizedBox.square(
      dimension: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: ConstellationFieldUnreadGlowPainter(
                frame: frame,
                glowSites: const {
                  'swatch': (authorId: 'author', opacity: 1),
                },
                colorForAuthor: (_) => tt.attentionHighlight,
                atlas: ConstellationFieldUnreadGlowAtlas.instance,
                spread: tt.fieldUnreadGlowSpread,
                alphaDark: tt.fieldUnreadGlowAlphaDark,
                alphaLight: tt.fieldUnreadGlowAlphaLight,
                unreadDotSize: tt.unreadDotSize,
                unreadDotColor: tt.info,
                isDark: scheme.brightness == Brightness.dark,
                highContrast: false,
                pulseBoost: 1,
              ),
            ),
          ),
          Icon(
            Icons.campaign_outlined,
            size: body.width * 0.85,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}
