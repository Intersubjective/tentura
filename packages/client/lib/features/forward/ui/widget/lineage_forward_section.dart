import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

typedef LineageClearCallback = void Function();

class LineageForwardSectionHeader extends StatelessWidget {
  const LineageForwardSectionHeader({
    required this.onClear,
    super.key,
  });

  final LineageClearCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(tt.screenHPadding, tt.rowGap, tt.screenHPadding, tt.rowGap * 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: tt.iconSize, color: tt.textMuted),
              SizedBox(width: tt.rowGap * 0.5),
              Expanded(
                child: Text(
                  l10n.beaconLineageForwardSectionTitle,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: l10n.beaconLineageForwardSectionHelp,
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      content: Text(l10n.beaconLineageForwardSectionHelp),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(l10n.buttonDismiss),
                        ),
                      ],
                    ),
                  );
                },
                icon: Icon(Icons.info_outline, color: tt.textMuted),
              ),
            ],
          ),
          Text(
            l10n.beaconLineageAutoSelectHint,
            style: TenturaText.bodySmall(tt.textMuted),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: onClear,
              child: Text(l10n.beaconLineageClearSuggestions),
            ),
          ),
        ],
      ),
    );
  }
}

String lineageReasonLabel(L10n l10n, String code, {String? arg}) =>
    switch (code) {
      'lineageReasonHelpedBefore' => l10n.lineageReasonHelpedBefore,
      'lineageReasonReviewedHelpful' => l10n.lineageReasonReviewedHelpful,
      'lineageReasonRoutedHelp' => l10n.lineageReasonRoutedHelp,
      'lineageReasonPrivateTag' => l10n.lineageReasonPrivateTag(arg ?? ''),
      _ => code,
    };
