import 'package:flutter/material.dart';

import '../tentura_spacing.dart';
import '../tentura_text.dart';
import '../tentura_tokens.dart';

/// A surface with nothing on it: what it is, why it is empty, what to do.
///
/// One bare grey line ("Nothing to follow yet.") says the list is empty but
/// not what would ever appear there or how to get something onto it. This
/// widget carries the three parts an empty state owes the reader — a glyph,
/// a title and one explanatory line — plus an optional way out.
///
/// For You's cleared/reward states stay with `ForYouEmptyState` /
/// `CaughtUpPanel`: they follow their own rules about what may be claimed.
class TenturaEmptyState extends StatelessWidget {
  const TenturaEmptyState({
    required this.icon,
    required this.title,
    this.body,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  static const titleKey = Key('tentura-empty-state-title');
  static const bodyKey = Key('tentura-empty-state-body');
  static const actionKey = Key('tentura-empty-state-action');

  final IconData icon;
  final String title;

  /// What would appear here and how it gets here. Never ellipsised.
  final String? body;

  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Center(
      child: SingleChildScrollView(
        padding: tt.cardPadding,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: TenturaSpacing.emptyStateMaxWidth,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExcludeSemantics(
                child: Icon(icon, size: tt.iconSize * 2, color: tt.textFaint),
              ),
              SizedBox(height: tt.rowGap),
              Text(
                title,
                key: titleKey,
                textAlign: TextAlign.center,
                style: TenturaText.titleSmall(tt.text),
              ),
              if (body != null) ...[
                SizedBox(height: tt.tightGap * 2),
                Text(
                  body!,
                  key: bodyKey,
                  textAlign: TextAlign.center,
                  style: TenturaText.bodySmall(tt.textMuted),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                SizedBox(height: tt.sectionGap),
                FilledButton.tonal(
                  key: actionKey,
                  onPressed: onAction,
                  child: Text(actionLabel!),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
