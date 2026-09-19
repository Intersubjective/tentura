import 'package:flutter/material.dart';

import '../tentura_radii.dart';
import '../tentura_text.dart';
import '../tentura_tokens.dart';

/// Relation the viewer has with a Request, as shown on a card header.
///
/// Relation chips are first-person labels about *me* («Помогаю» / «Слежу»),
/// never capability tags — those keep `ForwardCapabilityChips`.
enum TenturaRelationTone {
  helping,
  following;

  /// Chip fill for this tone, derived from the operational token palette.
  Color container(TenturaTokens tt) => switch (this) {
    TenturaRelationTone.helping => tt.good.withValues(alpha: 0.14),
    TenturaRelationTone.following => tt.info.withValues(alpha: 0.14),
  };

  /// Label / icon colour paired with [container].
  Color onContainer(TenturaTokens tt) => switch (this) {
    TenturaRelationTone.helping => tt.good,
    TenturaRelationTone.following => tt.info,
  };
}

/// Compact, read-only chip naming the viewer's relation to a Request.
///
/// Read-only by design: the relation is changed through named actions
/// («Предложить помощь», «Следить»), never by tapping the chip.
class TenturaRelationChip extends StatelessWidget {
  const TenturaRelationChip({
    required this.label,
    required this.tone,
    this.icon,
    this.semanticsLabel,
    super.key,
  });

  final String label;
  final TenturaRelationTone tone;
  final IconData? icon;

  /// Defaults to [label]; set when the chip needs a fuller spoken form.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final foreground = tone.onContainer(tt);
    final iconData = icon;
    return Semantics(
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tone.container(tt),
          borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tt.iconTextGap,
            vertical: tt.tightGap,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (iconData != null) ...[
                Icon(
                  iconData,
                  size: TenturaText.bodySmall(foreground).fontSize,
                  color: foreground,
                ),
                SizedBox(width: tt.tightGap),
              ],
              Text(label, style: TenturaText.labelSmall(foreground)),
            ],
          ),
        ),
      ),
    );
  }
}
