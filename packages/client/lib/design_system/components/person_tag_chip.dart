import 'package:flutter/material.dart';

import '../tentura_radii.dart';
import '../tentura_tag_colors.dart';
import '../tentura_text.dart';
import '../tentura_tokens.dart';

/// Round tag glyph (a letter or emoji) on the tag's accent colour.
class TagGlyph extends StatelessWidget {
  const TagGlyph({
    required this.glyph,
    required this.colorIndex,
    this.size = 20,
    super.key,
  });

  final String glyph;
  final int colorIndex;
  final double size;

  @override
  Widget build(BuildContext context) {
    final swatch = context.tagColors.swatchFor(colorIndex);
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(color: swatch.accent, shape: BoxShape.circle),
        child: Center(
          child: Text(
            glyph,
            style: TenturaText.labelSmall(
              swatch.container,
            ).copyWith(fontSize: size * 0.55, height: 1),
          ),
        ),
      ),
    );
  }
}

/// One of the viewer's own tags: glyph circle + name, with an optional ×.
///
/// The × is offered only when [onRemove] is set.
class PersonTagChip extends StatelessWidget {
  const PersonTagChip({
    required this.glyph,
    required this.name,
    required this.colorIndex,
    this.onRemove,
    super.key,
  });

  final String glyph;
  final String name;
  final int colorIndex;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final swatch = context.tagColors.swatchFor(colorIndex);
    final onRemove = this.onRemove;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: swatch.container,
        borderRadius: BorderRadius.circular(TenturaRadii.avatar),
      ),
      child: Padding(
        padding: EdgeInsets.all(tt.tightGap * 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              container: true,
              label: '$name, tag',
              excludeSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TagGlyph(glyph: glyph, colorIndex: colorIndex),
                  SizedBox(width: tt.iconTextGap),
                  Text(
                    name,
                    style: TenturaText.labelSmall(swatch.onContainer),
                  ),
                  SizedBox(width: tt.iconTextGap),
                ],
              ),
            ),
            if (onRemove != null)
              Semantics(
                button: true,
                label: MaterialLocalizations.of(context).deleteButtonTooltip,
                excludeSemantics: true,
                child: InkResponse(
                  onTap: onRemove,
                  radius: 14,
                  child: Icon(
                    Icons.close,
                    size: 16,
                    color: swatch.onContainer,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A tag the app derives on its own: outlined chip with a ✦ mark, never
/// removable. The outline turns dashed while the tag is switched off.
class AutoTagChip extends StatelessWidget {
  const AutoTagChip({
    required this.name,
    this.enabled = true,
    super.key,
  });

  final String name;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final foreground = enabled ? tt.text : tt.textMuted;
    return Semantics(
      label: '$name, automatic tag',
      excludeSemantics: true,
      child: CustomPaint(
        painter: _TagOutlinePainter(color: tt.border, dashed: !enabled),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tt.iconTextGap * 2,
            vertical: tt.tightGap * 2 + 2,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // RichText, not Text: one widget carries the mark.
              RichText(
                textScaler: MediaQuery.textScalerOf(context),
                text: TextSpan(
                  text: '✦',
                  style: TenturaText.labelSmall(foreground),
                ),
              ),
              SizedBox(width: tt.iconTextGap),
              Text(name, style: TenturaText.labelSmall(foreground)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill outline, one logical pixel wide and pixel-aligned; dashed on request.
class _TagOutlinePainter extends CustomPainter {
  const _TagOutlinePainter({required this.color, required this.dashed});

  static const _strokeWidth = 1.0;
  static const _dash = 4.0;
  static const _gap = 3.0;

  final Color color;
  final bool dashed;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    final rect = (Offset.zero & size).deflate(_strokeWidth / 2);
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide / 2)),
      );
    if (!dashed) {
      canvas.drawPath(path, paint);
      return;
    }
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += _dash + _gap) {
        canvas.drawPath(metric.extractPath(d, d + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_TagOutlinePainter old) =>
      old.color != color || old.dashed != dashed;
}
