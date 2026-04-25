import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Triage actions for beacon cards: Commit primary, Forward outlined, optional
/// tertiary (inbox: Not for me / stop watching; beacon detail: View chain).
class CardTriageActionRow extends StatelessWidget {
  const CardTriageActionRow({
    required this.onForward,
    this.onCommit,
    this.secondaryLabel,
    this.secondaryIcon,
    this.onSecondary,
    super.key,
  });

  final Future<void> Function()? onCommit;
  final VoidCallback onForward;
  final String? secondaryLabel;
  final IconData? secondaryIcon;
  final Future<void> Function()? onSecondary;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final hasCommit = onCommit != null;
    final hasSecondary =
        onSecondary != null &&
        (secondaryLabel != null || secondaryIcon != null);

    final commitFlex = hasSecondary ? 5 : 1;
    final forwardFlex = hasSecondary ? 4 : 1;

    final forwardBtn = OutlinedButton.icon(
      onPressed: onForward,
      icon: const Icon(Icons.send, size: 18),
      label: Text(
        l10n.labelForward,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      ),
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        alignment: Alignment.center,
      ),
    );

    final commitBtn = FilledButton.icon(
      onPressed: () async {
        await onCommit?.call();
      },
      icon: const Icon(Icons.handshake, size: 20),
      label: Text(
        l10n.labelCommit,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      ),
      style: FilledButton.styleFrom(
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        alignment: Alignment.center,
      ),
    );

    final tertiaryStyle = TextButton.styleFrom(
      foregroundColor: scheme.onSurfaceVariant,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    );

    return Row(
      children: [
        if (hasCommit) ...[
          Expanded(
            flex: commitFlex,
            child: commitBtn,
          ),
          const SizedBox(width: kSpacingSmall),
          Expanded(
            flex: forwardFlex,
            child: forwardBtn,
          ),
        ] else
          Expanded(child: forwardBtn),
        if (hasSecondary) ...[
          const SizedBox(width: kSpacingSmall),
          if (secondaryIcon != null && secondaryLabel != null)
            TextButton.icon(
              style: tertiaryStyle,
              onPressed: () async {
                await onSecondary?.call();
              },
              icon: Icon(secondaryIcon, size: 16),
              label: Text(
                secondaryLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            )
          else if (secondaryIcon != null)
            TextButton(
              style: tertiaryStyle,
              onPressed: () async {
                await onSecondary?.call();
              },
              child: Icon(secondaryIcon, size: 16),
            )
          else
            TextButton(
              style: tertiaryStyle,
              onPressed: () async {
                await onSecondary?.call();
              },
              child: Text(
                secondaryLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ],
    );
  }
}
