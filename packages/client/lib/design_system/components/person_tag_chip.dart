import 'package:flutter/material.dart';
import 'package:tentura/ui/l10n/l10n.dart';

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

/// Small ✦ for inherited own-tag membership (same mark as automatic tags).
class InheritedTagMarker extends StatelessWidget {
  const InheritedTagMarker({required this.color, super.key});

  final Color color;

  @override
  Widget build(BuildContext context) => RichText(
    textScaler: MediaQuery.textScalerOf(context),
    text: TextSpan(
      text: '✦',
      style: TenturaText.labelSmall(color),
    ),
  );
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
    this.onKeep,
    this.keepLabel,
    this.keepSemanticsLabel,
    this.showInheritedMarker = false,
    this.semanticsLabel,
    this.tooltipMessage,
    this.maxWidth,
    this.selected = false,
    super.key,
  });

  final String glyph;
  final String name;
  final int colorIndex;
  final VoidCallback? onRemove;
  final VoidCallback? onKeep;
  final String? keepLabel;
  final String? keepSemanticsLabel;
  final bool showInheritedMarker;

  /// When set, replaces the default «{name}, tag» screen-reader label.
  final String? semanticsLabel;

  /// Tooltip for inherited chips; defaults to [semanticsLabel] when inherited.
  final String? tooltipMessage;
  final bool selected;

  /// When set (e.g. in a wrapped tag list), the name ellipsizes instead of
  /// overflowing the line.
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final swatch = context.tagColors.swatchFor(colorIndex);
    final onRemove = this.onRemove;
    final onKeep = this.onKeep;
    final maxWidth = this.maxWidth;
    final selected = this.selected;
    final chipSemantics =
        semanticsLabel ??
        L10n.of(context)?.peopleTagsPersonChipSemantics(name) ??
        '$name, tag';
    Widget namePart = Text(
      name,
      style: TenturaText.labelSmall(swatch.onContainer),
    );
    if (maxWidth != null) {
      namePart = Expanded(
        child: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TenturaText.labelSmall(swatch.onContainer),
        ),
      );
    }
    final labelRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selected) ...[
          Icon(Icons.check, size: 16, color: scheme.primary),
          SizedBox(width: tt.tightGap),
        ],
        TagGlyph(glyph: glyph, colorIndex: colorIndex),
        SizedBox(width: tt.iconTextGap),
        namePart,
        if (showInheritedMarker) ...[
          SizedBox(width: tt.iconTextGap),
          InheritedTagMarker(color: swatch.onContainer),
        ],
        SizedBox(width: tt.iconTextGap),
      ],
    );
    final labelSemantics = Semantics(
      container: true,
      label: chipSemantics,
      excludeSemantics: true,
      child: labelRow,
    );
    Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (maxWidth != null)
          Expanded(child: labelSemantics)
        else
          labelSemantics,
        if (onKeep != null)
          Semantics(
            button: true,
            label: keepSemanticsLabel ?? keepLabel,
            excludeSemantics: true,
            child: InkResponse(
              onTap: onKeep,
              radius: 14,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: tt.tightGap),
                child: Text(
                  keepLabel ?? '',
                  style: TenturaText.labelSmall(swatch.onContainer),
                ),
              ),
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
              child: Icon(Icons.close, size: 16, color: swatch.onContainer),
            ),
          ),
      ],
    );
    if (maxWidth != null) {
      row = SizedBox(width: maxWidth, child: row);
    }
    final fill = selected
        ? Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.12),
            swatch.container,
          )
        : swatch.container;
    final chip = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(TenturaRadii.avatar),
        border: selected ? Border.all(color: scheme.primary, width: 2) : null,
      ),
      child: Padding(padding: EdgeInsets.all(tt.tightGap * 2), child: row),
    );
    final tip = tooltipMessage ?? semanticsLabel;
    if (tip != null && tip.isNotEmpty) {
      return Tooltip(message: tip, child: chip);
    }
    return chip;
  }
}

/// A tag the app derives on its own: outlined chip with a ✦ mark, never
/// removable. The outline turns dashed while the tag is switched off.
class AutoTagChip extends StatelessWidget {
  const AutoTagChip({
    required this.name,
    this.enabled = true,
    this.selected = false,
    super.key,
  });

  final String name;
  final bool enabled;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final foreground = enabled ? tt.text : tt.textMuted;
    final chipSemantics =
        L10n.of(context)?.peopleTagsAutoChipSemantics(name) ??
        '$name, automatic tag';
    final outlineColor = selected ? scheme.primary : tt.border;
    final dashed = !enabled && !selected;
    final fill = selected
        ? Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.12),
            scheme.surfaceContainerHighest,
          )
        : null;
    return Semantics(
      label: chipSemantics,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(TenturaRadii.avatar),
        ),
        child: CustomPaint(
          painter: _TagOutlinePainter(
            color: outlineColor,
            dashed: dashed,
            strokeWidth: selected ? 2 : _TagOutlinePainter.defaultStrokeWidth,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: tt.iconTextGap * 2,
              vertical: tt.tightGap * 2 + 2,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  Icon(Icons.check, size: 16, color: scheme.primary),
                  SizedBox(width: tt.tightGap),
                ],
                // RichText, not Text: one widget carries the mark.
                RichText(
                  textScaler: MediaQuery.textScalerOf(context),
                  text: TextSpan(
                    text: '✦',
                    style: TenturaText.labelSmall(
                      selected ? scheme.primary : foreground,
                    ),
                  ),
                ),
                SizedBox(width: tt.iconTextGap),
                Text(
                  name,
                  style: TenturaText.labelSmall(
                    selected ? scheme.primary : foreground,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pill outline, one logical pixel wide and pixel-aligned; dashed on request.
class _TagOutlinePainter extends CustomPainter {
  const _TagOutlinePainter({
    required this.color,
    required this.dashed,
    this.strokeWidth = defaultStrokeWidth,
  });

  static const defaultStrokeWidth = 1.0;
  static const _dash = 4.0;
  static const _gap = 3.0;

  final Color color;
  final bool dashed;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rect = (Offset.zero & size).deflate(strokeWidth / 2);
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
      old.color != color ||
      old.dashed != dashed ||
      old.strokeWidth != strokeWidth;
}
