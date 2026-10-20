import 'dart:ui' as ui;

import 'dart:math' show max, min, pow, sqrt;

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/design_system/tentura_radii.dart';
import 'package:tentura/design_system/tentura_spacing.dart';
import 'package:tentura/design_system/tentura_tokens.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

import '../bloc/rating_cubit.dart';
import '../util/stable_scatter_jitter.dart';

const _canvasWidth = 800.0;
const _canvasHeight = 800.0;
const _avatarSize = 32.0;
const _plotMargin = 40.0; // margin so avatars at 0% or 100% are fully visible
const _minScale = 0.08;
const _maxScale = 4.0;
const _borderStretchExponent = 2.0;
const _labelWidth = 100.0;
const _labelHeight = 20.0;
const _avatarLabelGap = 2.0;
const _zoomDuration = Duration(milliseconds: 250);

/// Share of a column's box another column may cover before they cluster.
const _clusterOverlapShare = 0.15;

class RatingScatterView extends StatefulWidget {
  const RatingScatterView({
    required this.profiles,
    super.key,
  });

  final List<Profile> profiles;

  /// Clustering passes run so far (#462 review): tests check that panning
  /// reuses the cached clusters.
  @visibleForTesting
  static int debugClusterComputations = 0;

  @override
  State<RatingScatterView> createState() => _RatingScatterViewState();
}

class _RatingScatterViewState extends State<RatingScatterView>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformController =
      TransformationController();

  late final AnimationController _zoomAnimation;

  Matrix4Tween? _zoomTween;

  /// Size of the plot area (viewport of the InteractiveViewer).
  Size _plotSize = const Size(_canvasWidth, _canvasHeight);

  /// Canvas-space clusters (zoom <= 1): one pass per profiles / self id.
  _ClusterCache? _canvasCache;

  /// Clusters in scaled child space (zoom > 1), translation excluded: one
  /// pass per scale / plot size; pure pans only offset them.
  _ClusterCache? _overlayCache;

  @override
  void initState() {
    super.initState();
    _zoomAnimation = AnimationController(vsync: this, duration: _zoomDuration)
      ..addListener(_onZoomTick);
  }

  @override
  void didUpdateWidget(covariant RatingScatterView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.profiles, widget.profiles)) {
      _canvasCache = null;
      _overlayCache = null;
    }
  }

  @override
  void dispose() {
    _zoomAnimation.dispose();
    _transformController.dispose();
    super.dispose();
  }

  void _onZoomTick() {
    final tween = _zoomTween;
    if (tween == null) return;
    _transformController.value = tween.evaluate(
      CurvedAnimation(parent: _zoomAnimation, curve: Curves.easeOut),
    );
  }

  /// Scale factor from InteractiveViewer's matrix (approx for scale+translate).
  static double _scaleFromMatrix(Matrix4 m) {
    final sum = (m.entry(0, 0) * m.entry(0, 0) + m.entry(1, 0) * m.entry(1, 0))
        .clamp(0.0, double.infinity);
    return sqrt(sum);
  }

  /// FittedBox scale from the 800x800 canvas to the plot area.
  static double _fitScale(Size plot) =>
      (plot.width.isFinite &&
          plot.height.isFinite &&
          plot.width > 0 &&
          plot.height > 0)
      ? (plot.width / _canvasWidth).clamp(0.0, plot.height / _canvasHeight)
      : 1.0;

  /// Map a canvas point to child space (FittedBox output, before the
  /// InteractiveViewer's transform).
  static Offset _canvasToChild(Offset canvas, Size plot) {
    final fitScale = _fitScale(plot);
    return Offset(
      plot.width / 2 + (canvas.dx - _canvasWidth / 2) * fitScale,
      plot.height / 2 + (canvas.dy - _canvasHeight / 2) * fitScale,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final tt = context.tt;
    final axisTitleStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    // Axis titles (#462): x = how they rank you (rScore), y = how you rank
    // them (score). Each sits in its own gutter outside the plot area, so
    // neither covers the avatars at rank 0.
    final plot = Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: tt.tightGap),
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Text(l10n.rankFromYou, style: axisTitleStyle),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) =>
                      _buildPlotArea(context, constraints.biggest),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.symmetric(vertical: tt.tightGap),
          child: Text(l10n.rankToYou, style: axisTitleStyle),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) =>
          constraints.hasBoundedWidth && constraints.hasBoundedHeight
          ? plot
          : SizedBox(
              width: constraints.hasBoundedWidth
                  ? constraints.maxWidth
                  : _canvasWidth,
              height: constraints.hasBoundedHeight
                  ? constraints.maxHeight
                  : _canvasHeight,
              child: plot,
            ),
    );
  }

  Widget _buildPlotArea(BuildContext context, Size plotSize) {
    final l10n = L10n.of(context)!;
    _plotSize = plotSize;
    return Stack(
      children: [
        InteractiveViewer(
          transformationController: _transformController,
          constrained: false,
          minScale: _minScale,
          maxScale: _maxScale,
          onInteractionStart: (_) => _zoomAnimation.stop(),
          child: SizedBox(
            width: plotSize.width,
            height: plotSize.height,
            child: FittedBox(
              child: SizedBox(
                width: _canvasWidth,
                height: _canvasHeight,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CustomPaint(
                      size: const Size(_canvasWidth, _canvasHeight),
                      painter: _QuadrantBackgroundPainter(
                        margin: _plotMargin,
                        quadrantMyIdols: l10n.quadrantMyIdols,
                        quadrantMyFriends: l10n.quadrantMyFriends,
                        quadrantAcquaintances: l10n.quadrantAcquaintances,
                        quadrantMyFans: l10n.quadrantMyFans,
                      ),
                    ),
                    // Avatars in canvas (scaled with plot) when zoom <= 1
                    ListenableBuilder(
                      listenable: _transformController,
                      builder: (context, _) {
                        final scale = _scaleFromMatrix(
                          _transformController.value,
                        );
                        if (scale > 1.0) return const SizedBox.shrink();
                        return _buildScatterPlotAvatars(context);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Fixed-size avatars in viewport when zoom > 1
        ListenableBuilder(
          listenable: _transformController,
          builder: (context, _) {
            final scale = _scaleFromMatrix(_transformController.value);
            if (scale <= 1.0) return const SizedBox.shrink();
            return _buildAvatarOverlay(context, plotSize, scale);
          },
        ),
      ],
    );
  }

  /// Canvas-space centre of a profile's avatar (plot mapping + stable jitter).
  static Offset _canvasAnchor(Profile profile) {
    const plotW = _canvasWidth - 2 * _plotMargin;
    const plotH = _canvasHeight - 2 * _plotMargin;
    final mappedR = _stretchBorders(_clamp(profile.rScore));
    final mappedS = _stretchBorders(_clamp(profile.score));
    final jitter = _jitterFor(profile.id);
    return Offset(
      _plotMargin + mappedR / 100 * plotW + jitter.dx,
      _plotMargin + (1 - mappedS / 100) * plotH + jitter.dy,
    );
  }

  /// Box covered by an avatar + name column whose avatar centre is [anchor].
  static Rect _columnRect(Offset anchor) => Rect.fromLTWH(
    anchor.dx - _labelWidth / 2,
    anchor.dy - _avatarSize / 2,
    _labelWidth,
    _avatarSize + _avatarLabelGap + _labelHeight,
  );

  /// Greedy clustering (#462): people whose avatar/name columns would pile on
  /// top of each other are folded into the first placed column they hit,
  /// which then shows a "+N" chip (N = hidden members). Self goes first, then
  /// higher ranked people, so the most relevant faces stay visible. Zooming
  /// in recomputes this in viewport space, which splits clusters apart.
  static List<_ScatterCluster> _clusterPoints(
    List<Profile> profiles,
    Offset Function(Profile) anchorOf,
    String myId,
  ) {
    RatingScatterView.debugClusterComputations++;
    final ordered = [...profiles]
      ..sort((a, b) {
        final aSelf = SelfUserHighlight.profileIsSelf(a, myId);
        final bSelf = SelfUserHighlight.profileIsSelf(b, myId);
        if (aSelf != bSelf) return aSelf ? -1 : 1;
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        final byRScore = b.rScore.compareTo(a.rScore);
        if (byRScore != 0) return byRScore;
        return a.id.compareTo(b.id);
      });
    final clusters = <_ScatterCluster>[];
    for (final profile in ordered) {
      final anchor = anchorOf(profile);
      final rect = _columnRect(anchor);
      _ScatterCluster? host;
      for (final c in clusters) {
        if (_overlapShare(rect, c.rect) > _clusterOverlapShare) {
          host = c;
          break;
        }
      }
      if (host == null) {
        clusters.add(_ScatterCluster(profile, anchor, rect));
      } else {
        host.hidden.add(profile);
      }
    }
    return clusters;
  }

  static double _overlapShare(Rect a, Rect b) {
    final i = a.intersect(b);
    if (i.width <= 0 || i.height <= 0) return 0;
    final area = a.width * a.height;
    return area <= 0 ? 0 : (i.width * i.height) / area;
  }

  /// Positions each profile avatar on the merit scatter plot by rScore/score
  /// coordinates (with per-id jitter). Colliding points are clustered once
  /// per profiles / self id; pans and zoom-out reuse the result.
  Widget _buildScatterPlotAvatars(BuildContext context) {
    final myId = context.watch<ProfileCubit>().state.profile.id;
    final cache = _canvasCache;
    final clusters =
        cache != null && cache.matches(widget.profiles, myId, 0, Size.zero)
        ? cache.clusters
        : (_canvasCache = _ClusterCache(
            profiles: widget.profiles,
            myId: myId,
            scale: 0,
            plotSize: Size.zero,
            clusters: _clusterPoints(widget.profiles, _canvasAnchor, myId),
          )).clusters;
    return Stack(
      clipBehavior: Clip.none,
      children: [for (final c in clusters) _buildPoint(context, c, myId)],
    );
  }

  /// Zoomed-in avatars at a fixed size. Clusters live in scaled child space
  /// (translation excluded) and are recomputed only when the scale or the
  /// plot size changes; a pure pan just offsets them.
  Widget _buildAvatarOverlay(
    BuildContext context,
    Size plotSize,
    double scale,
  ) {
    final myId = context.watch<ProfileCubit>().state.profile.id;
    final matrix = _transformController.value;
    final cache = _overlayCache;
    final clusters =
        cache != null && cache.matches(widget.profiles, myId, scale, plotSize)
        ? cache.clusters
        : (_overlayCache = _ClusterCache(
            profiles: widget.profiles,
            myId: myId,
            scale: scale,
            plotSize: plotSize,
            clusters: _clusterPoints(
              widget.profiles,
              (profile) =>
                  _canvasToChild(_canvasAnchor(profile), plotSize) * scale,
              myId,
            ),
          )).clusters;
    // Offsetting each Positioned (rather than translating the whole layer)
    // keeps every visible column inside the Stack's bounds, so it stays
    // tappable after a pan.
    final pan = Offset(matrix.entry(0, 3), matrix.entry(1, 3));
    return SizedBox(
      width: plotSize.width,
      height: plotSize.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final c in clusters) _buildPoint(context, c, myId, offset: pan),
        ],
      ),
    );
  }

  /// "+N" chip tap (#462 review): zoom in around the cluster, far enough
  /// that its members' columns stop overlapping, instead of opening the lead.
  void _zoomIntoCluster(_ScatterCluster c) {
    final plot = _plotSize;
    final fit = _fitScale(plot);
    final members = [c.lead, ...c.hidden];
    final anchors = [for (final p in members) _canvasAnchor(p)];
    var bounds = Rect.fromPoints(anchors.first, anchors.first);
    for (final a in anchors) {
      bounds = bounds.expandToInclude(Rect.fromPoints(a, a));
    }
    final current = _scaleFromMatrix(_transformController.value);
    // Scale at which the members' spread covers a whole column on both axes
    // (the larger need), so the cluster reliably splits; capped at max zoom.
    double need(double extent, double column) =>
        extent * fit <= 0 ? _maxScale : column / (extent * fit);
    final target = [
      need(bounds.width, _labelWidth),
      need(bounds.height, _avatarSize + _avatarLabelGap + _labelHeight),
    ].reduce(max).clamp(min(current * 2, _maxScale), _maxScale).toDouble();
    if (target <= current) return;
    final centre = _canvasToChild(bounds.center, plot);
    double translate(double viewport, double child) =>
        (viewport / 2 - target * child)
            .clamp(min(viewport - target * viewport, 0), 0)
            .toDouble();
    final end = Matrix4.diagonal3Values(target, target, 1)
      ..setTranslationRaw(
        translate(plot.width, centre.dx),
        translate(plot.height, centre.dy),
        0,
      );
    _zoomTween = Matrix4Tween(begin: _transformController.value, end: end);
    _zoomAnimation.forward(from: 0);
  }

  /// Avatar + name column for a cluster lead, with a "+N" chip when others
  /// are hidden behind it.
  Widget _buildPoint(
    BuildContext context,
    _ScatterCluster c,
    String myId, {
    Offset offset = Offset.zero,
  }) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final profile = c.lead;
    final isSelf = SelfUserHighlight.profileIsSelf(profile, myId);
    final avatarCore = TenturaAvatar(
      profile: profile,
      size: _avatarSize,
      withRating: true,
      isSelf: isSelf,
    );
    return Positioned(
      left: c.rect.left + offset.dx,
      top: c.rect.top + offset.dy,
      width: _labelWidth,
      child: GestureDetector(
        onTap: () => context.read<RatingCubit>().showProfile(profile.id),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: _labelWidth,
              height: _avatarSize,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  avatarCore,
                  if (c.hidden.isNotEmpty)
                    Positioned(
                      left: _labelWidth / 2 + _avatarSize / 2 - 6,
                      top: -4,
                      child: Semantics(
                        container: true,
                        button: true,
                        label: l10n.ratingScatterClusterMore(c.hidden.length),
                        excludeSemantics: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _zoomIntoCluster(c),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: TenturaSpacing.tight * 2,
                              vertical: TenturaSpacing.tight / 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(
                                TenturaRadii.cardDense,
                              ),
                            ),
                            child: Text(
                              '+${c.hidden.length}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: _avatarLabelGap),
            SizedBox(
              width: _labelWidth,
              height: _labelHeight,
              child: Text(
                SelfUserHighlight.displayName(l10n, profile, myId),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
                style: SelfUserHighlight.nameStyle(
                  theme,
                  theme.textTheme.bodySmall,
                  isSelf,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static double _clamp(double value) {
    if (value.isNaN || value.isInfinite) return 0;
    if (value < 0) return 0;
    if (value > 100) return 100;
    return value;
  }

  /// Maps [0, 100] to [0, 100] with stretch at borders and compression at center.
  static double _stretchBorders(
    double value, {
    double exponent = _borderStretchExponent,
  }) {
    final t = (value.clamp(0.0, 100.0)) / 100;
    final u = 2 * t - 1;
    final v = u.sign * pow(u.abs().clamp(0.0, 1.0), exponent).toDouble();
    return (0.5 + 0.5 * v) * 100;
  }

  static Offset _jitterFor(String id) => scatterPlotJitterOffsetForId(id);
}

class _ClusterCache {
  _ClusterCache({
    required this.profiles,
    required this.myId,
    required this.scale,
    required this.plotSize,
    required this.clusters,
  });

  final List<Profile> profiles;
  final String myId;
  final double scale;
  final Size plotSize;
  final List<_ScatterCluster> clusters;

  bool matches(List<Profile> p, String id, double s, Size size) =>
      identical(p, profiles) && id == myId && s == scale && size == plotSize;
}

class _ScatterCluster {
  _ScatterCluster(this.lead, this.anchor, this.rect);

  final Profile lead;
  final Offset anchor;
  final Rect rect;
  final List<Profile> hidden = [];
}

class _QuadrantBackgroundPainter extends CustomPainter {
  _QuadrantBackgroundPainter({
    required this.margin,
    required this.quadrantMyIdols,
    required this.quadrantMyFriends,
    required this.quadrantAcquaintances,
    required this.quadrantMyFans,
  });

  final double margin;
  final String quadrantMyIdols;
  final String quadrantMyFriends;
  final String quadrantAcquaintances;
  final String quadrantMyFans;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final plotLeft = margin;
    final plotTop = margin;
    final plotW = w - 2 * margin;
    final plotH = h - 2 * margin;
    final cx = plotLeft + plotW / 2;
    final cy = plotTop + plotH / 2;

    // Crosshair at 50% of plot area
    final linePaint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    canvas
      ..drawLine(Offset(cx, plotTop), Offset(cx, plotTop + plotH), linePaint)
      ..drawLine(Offset(plotLeft, cy), Offset(plotLeft + plotW, cy), linePaint);

    // Semi-transparent quadrant labels (centers of each plot quadrant)
    final textStyle = TextStyle(
      fontSize: 18,
      color: Colors.grey.withValues(alpha: 0.4),
      fontWeight: FontWeight.w500,
    );

    _drawLabel(
      canvas,
      quadrantMyIdols,
      Offset(plotLeft + plotW / 4, plotTop + plotH / 4),
      textStyle,
    );
    _drawLabel(
      canvas,
      quadrantMyFriends,
      Offset(plotLeft + 3 * plotW / 4, plotTop + plotH / 4),
      textStyle,
    );
    _drawLabel(
      canvas,
      quadrantAcquaintances,
      Offset(plotLeft + plotW / 4, plotTop + 3 * plotH / 4),
      textStyle,
    );
    _drawLabel(
      canvas,
      quadrantMyFans,
      Offset(plotLeft + 3 * plotW / 4, plotTop + 3 * plotH / 4),
      textStyle,
    );
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset center,
    TextStyle textStyle,
  ) {
    final builder =
        ui.ParagraphBuilder(
            ui.ParagraphStyle(
              fontSize: textStyle.fontSize,
              fontFamily: textStyle.fontFamily,
              fontWeight: textStyle.fontWeight,
            ),
          )
          ..pushStyle(ui.TextStyle(color: textStyle.color))
          ..addText(text);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 200));
    canvas.drawParagraph(
      paragraph,
      Offset(
        center.dx - paragraph.width / 2,
        center.dy - paragraph.height / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(covariant _QuadrantBackgroundPainter oldDelegate) =>
      oldDelegate.margin != margin ||
      oldDelegate.quadrantMyIdols != quadrantMyIdols ||
      oldDelegate.quadrantMyFriends != quadrantMyFriends ||
      oldDelegate.quadrantAcquaintances != quadrantAcquaintances ||
      oldDelegate.quadrantMyFans != quadrantMyFans;
}
