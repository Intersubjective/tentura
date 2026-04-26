import 'package:flutter/material.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Owner CTA row stacks vertically below this width (`BeaconPrimaryCtaBar`).
const double kCardTriageActionRowNarrowMaxWidth = 380;

/// Triage actions for beacon cards: Commit primary, Forward outlined, optional
/// tertiary (beacon detail: View chain as icon-only on the right).
class CardTriageActionRow extends StatelessWidget {
  const CardTriageActionRow({
    required this.onForward,
    this.onCommit,
    this.secondaryLabel,
    this.secondaryIcon,
    this.secondaryTooltip,
    this.onSecondary,
    super.key,
  });

  final Future<void> Function()? onCommit;
  final VoidCallback onForward;
  final String? secondaryLabel;
  final IconData? secondaryIcon;

  /// Shown for icon-only tertiary (a11y / long-press hint).
  final String? secondaryTooltip;

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

    Widget? tertiary;
    if (hasSecondary) {
      Future<void> onTap() async {
        await onSecondary?.call();
      }

      if (secondaryIcon != null && secondaryLabel != null) {
        tertiary = TextButton.icon(
          style: tertiaryStyle,
          onPressed: () async {
            await onTap();
          },
          icon: Icon(secondaryIcon, size: 16),
          label: Text(
            secondaryLabel!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      } else if (secondaryIcon != null) {
        final tip = secondaryTooltip?.trim();
        tertiary = IconButton(
          onPressed: () async {
            await onTap();
          },
          icon: Icon(secondaryIcon, size: 22),
          style: IconButton.styleFrom(
            foregroundColor: scheme.onSurfaceVariant,
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.all(8),
            minimumSize: const Size(44, 44),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          tooltip: tip != null && tip.isNotEmpty ? tip : null,
        );
      } else {
        tertiary = TextButton(
          style: tertiaryStyle,
          onPressed: () async {
            await onTap();
          },
          child: Text(
            secondaryLabel!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }
    }

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
        if (hasSecondary && tertiary != null) ...[
          const SizedBox(width: kSpacingSmall),
          tertiary,
        ],
      ],
    );
  }
}
