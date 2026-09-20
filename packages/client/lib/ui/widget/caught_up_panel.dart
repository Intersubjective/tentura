import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

/// U17d / D18 — "cleared states reward attention completion, not the
/// disappearance of work".
///
/// Copy-agnostic on purpose: every sentence is passed in, so the widget can
/// be the same reward on For you and the quiet note on My Desk without
/// carrying either surface's rules. The *rule* that decides whether a surface
/// is in this state stays where it already lives (`forYouEmptyKind`,
/// `shouldShowForYouEmptyState`) — a second copy of it here would be the
/// defect M1 names.
///
/// What it deliberately does **not** do: claim the screen is empty, count
/// streaks, or say anything the caller did not give it. [clearedLabel] is the
/// number one explicit sweep actually achieved; with no sweep there is no
/// number, and D18 forbids inventing one.
class CaughtUpPanel extends StatelessWidget {
  const CaughtUpPanel({
    required this.title,
    this.detail,
    this.clearedLabel,
    this.compact = false,
    super.key,
  });

  static const panelKey = Key('caught-up-panel');
  static const illustrationKey = Key('caught-up-illustration');
  static const titleKey = Key('caught-up-title');
  static const detailKey = Key('caught-up-detail');
  static const clearedKey = Key('caught-up-cleared');

  /// "You're caught up" — the headline, never a promise about the whole
  /// screen.
  final String title;

  /// Why something may still be above this panel. Rendered in full: it is the
  /// sentence that keeps the headline honest, so it is the last thing that
  /// may be truncated.
  final String? detail;

  /// "Cleared N" — the real result of one explicit sweep, or nothing.
  final String? clearedLabel;

  /// A single quiet line, for a surface whose work is still listed below it.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final label = [title, ?detail, ?clearedLabel].join('. ');

    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(
        child: Padding(
          key: panelKey,
          padding: compact
              ? EdgeInsets.symmetric(
                  horizontal: tt.rowGap,
                  vertical: tt.tightGap,
                )
              : tt.cardPadding,
          child: compact ? _compact(tt) : _full(tt),
        ),
      ),
    );
  }

  Widget _compact(TenturaTokens tt) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.check_circle_outline, size: tt.iconSize, color: tt.good),
      SizedBox(width: tt.iconTextGap),
      Flexible(
        child: Text(
          title,
          key: titleKey,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TenturaText.bodySmall(tt.textMuted),
        ),
      ),
    ],
  );

  Widget _full(TenturaTokens tt) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      _CaughtUpIllustration(tt: tt),
      SizedBox(height: tt.rowGap),
      Text(
        title,
        key: titleKey,
        textAlign: TextAlign.center,
        style: TenturaText.title(tt.text),
      ),
      if (detail != null) ...[
        SizedBox(height: tt.tightGap),
        // Unclipped and unellipsised: at narrow width and large text scale
        // this is the block that would otherwise be quietly cut, taking the
        // count below it with it.
        Text(
          detail!,
          key: detailKey,
          textAlign: TextAlign.center,
          style: TenturaText.bodySmall(tt.textMuted),
        ),
      ],
      if (clearedLabel != null) ...[
        SizedBox(height: tt.tightGap),
        Text(
          clearedLabel!,
          key: clearedKey,
          textAlign: TextAlign.center,
          style: TenturaText.bodySmall(tt.good),
        ),
      ],
    ],
  );
}

/// The lightweight illustration: one glyph, on the design system's own
/// "good" token, that fades in once — and does not fade at all when the
/// platform asks for reduced motion.
class _CaughtUpIllustration extends StatelessWidget {
  const _CaughtUpIllustration({required this.tt});

  final TenturaTokens tt;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      key: CaughtUpPanel.illustrationKey,
      tween: Tween(begin: reduceMotion ? 1 : 0, end: 1),
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      builder: (context, value, child) =>
          Opacity(opacity: value, child: child),
      child: Icon(
        Icons.task_alt,
        // Twice a row icon: an illustration, still a token multiple.
        size: tt.iconSize * 2,
        color: tt.good,
      ),
    );
  }
}
