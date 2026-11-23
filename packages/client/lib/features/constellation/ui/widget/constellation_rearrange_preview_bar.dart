import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Preview bar of «Rearrange everyone»: how many people will move, with Apply
/// and Cancel.
class ConstellationRearrangePreviewBar extends StatelessWidget {
  const ConstellationRearrangePreviewBar({
    required this.movingCount,
    required this.onApply,
    required this.onCancel,
    super.key,
  });

  final int movingCount;
  final VoidCallback onApply;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final summary = Text(
      l10n.constellationRearrangePreview(movingCount),
      style: TenturaText.status(theme.colorScheme.onSecondaryContainer),
    );
    final actions = [
      TextButton(
        key: const Key('constellation-rearrange-cancel'),
        onPressed: onCancel,
        child: Text(l10n.buttonCancel),
      ),
      TextButton(
        key: const Key('constellation-rearrange-apply'),
        onPressed: onApply,
        child: Text(l10n.planEditApply),
      ),
    ];
    return Material(
      color: theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tt.screenHPadding,
          vertical: tt.tightGap,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (windowClassForWidth(constraints.maxWidth) ==
                WindowClass.compact) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  summary,
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    overflowAlignment: OverflowBarAlignment.end,
                    children: actions,
                  ),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: summary),
                ...actions,
              ],
            );
          },
        ),
      ),
    );
  }
}
