import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/closure/domain/closure_split.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/features/closure/domain/silent_preview.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Live bars: what each member would get if the colleagues stay silent.
class ClosurePreview extends StatelessWidget {
  const ClosurePreview({
    required this.data,
    required this.beaconId,
    super.key,
  });

  final ClosureState data;

  /// Tie-break seed of the split rounding, as on the server.
  final String beaconId;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final shares = silentPreview(
      outcomes: {for (final m in data.members) m.id: data.outcomes?[m.id]},
      split: data.split,
      leftVoluntarily: closureVoluntaryLeavers(data),
      beaconId: beaconId,
    );
    final top = shares.values.fold<double>(0, (a, b) => a > b ? a : b);
    final total = shares.values.fold<double>(0, (a, b) => a + b);
    // Each row carries its value; a row with no share, or a preview with
    // nothing to show, is left out rather than drawn as a bare name (#733).
    final shown = [
      for (final m in data.members)
        if ((shares[m.id] ?? 0) > 0) m,
    ];
    if (shown.isEmpty || total <= 0) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.closureAuthorPreviewTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: TenturaSpacing.row),
        for (final m in shown)
          Padding(
            padding: const EdgeInsets.only(bottom: TenturaSpacing.row),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.closureAuthorSplitShare(
                    m.displayName ?? m.id,
                    (shares[m.id]! / total * 100).round(),
                  ),
                  key: ValueKey('closure.author.preview.value.${m.id}'),
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: TenturaSpacing.tight),
                FractionallySizedBox(
                  key: ValueKey('closure.author.preview.${m.id}'),
                  widthFactor: shares[m.id]! / top,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(
                        TenturaRadii.accentBar,
                      ),
                    ),
                    child: const SizedBox(height: TenturaSpacing.row),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
