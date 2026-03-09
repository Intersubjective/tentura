import 'dart:ui' as ui;

import 'dart:math' show pow;

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';

import '../bloc/rating_cubit.dart';

const _canvasWidth = 800.0;
const _canvasHeight = 800.0;
const _avatarSize = 32.0;
const _plotMargin = 40.0; // margin so avatars at 0% or 100% are fully visible
const _jitterRange = 8.0;
const _minScale = 0.08;
const _maxScale = 4.0;
const _borderStretchExponent = 2.0;
const _labelWidth = 100.0;
const _labelHeight = 20.0;
const _avatarLabelGap = 2.0;

class RatingScatterView extends StatefulWidget {
  const RatingScatterView({
    required this.profiles,
    super.key,
  });

  final List<Profile> profiles;

  @override
  State<RatingScatterView> createState() => _RatingScatterViewState();
}

class _RatingScatterViewState extends State<RatingScatterView> {
  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportW = constraints.maxWidth;
        final viewportH = constraints.maxHeight;
        return InteractiveViewer(
          constrained: false,
          minScale: _minScale,
          maxScale: _maxScale,
          child: SizedBox(
            width: viewportW.isFinite && viewportW > 0 ? viewportW : _canvasWidth,
            height:
                viewportH.isFinite && viewportH > 0 ? viewportH : _canvasHeight,
            child: FittedBox(
              fit: BoxFit.contain,
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
                    ...widget.profiles.map((profile) {
                      final plotW =
                          _canvasWidth - 2 * _plotMargin;
                      final plotH =
                          _canvasHeight - 2 * _plotMargin;
                      final mappedR =
                          _stretchBorders(_clamp(profile.rScore));
                      final mappedS =
                          _stretchBorders(_clamp(profile.score));
                      final x = _plotMargin + mappedR / 100 * plotW;
                      final y =
                          _plotMargin + (1 - mappedS / 100) * plotH;
                      final jitter = _jitterFor(profile.id);
                      final colW = _labelWidth;
                      final colLeft =
                          x - colW / 2 + jitter.dx;
                      final colTop =
                          y - _avatarSize / 2 + jitter.dy;
                      return Positioned(
                        left: colLeft,
                        top: colTop,
                        width: colW,
                        child: GestureDetector(
                          onTap: () => context
                              .read<RatingCubit>()
                              .showProfile(profile.id),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment:
                                CrossAxisAlignment.center,
                            children: [
                              AvatarRated(
                                profile: profile,
                                size: _avatarSize,
                              ),
                              SizedBox(height: _avatarLabelGap),
                              SizedBox(
                                width: _labelWidth,
                                height: _labelHeight,
                                child: Text(
                                  profile.title,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  static double _clamp(double value) {
    if (value.isNaN || value.isInfinite) return 0;
    if (value < 0) return 0;
    if (value > 100) return 100;
    return value;
  }

  /// Maps [0, 100] to [0, 100] with stretch at borders and compression at center.
  static double _stretchBorders(double value,
      {double exponent = _borderStretchExponent}) {
    final t = (value.clamp(0.0, 100.0)) / 100;
    final u = 2 * t - 1;
    final v = u.sign * pow(u.abs().clamp(0.0, 1.0), exponent).toDouble();
    return (0.5 + 0.5 * v) * 100;
  }

  static Offset _jitterFor(String id) {
    final h = Object.hash(id, 0);
    final h2 = Object.hash(id, 1);
    final dx = ((h % 1000) / 1000.0 * 2 - 1) * _jitterRange;
    final dy = ((h2 % 1000) / 1000.0 * 2 - 1) * _jitterRange;
    return Offset(dx, dy);
  }
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
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        fontSize: textStyle.fontSize,
        fontFamily: textStyle.fontFamily,
        fontWeight: textStyle.fontWeight,
      ),
    )
      ..pushStyle(ui.TextStyle(color: textStyle.color))
      ..addText(text);
    final paragraph = builder.build()
      ..layout(const ui.ParagraphConstraints(width: 200.0));
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
