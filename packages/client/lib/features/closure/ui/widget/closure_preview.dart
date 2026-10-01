import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/closure/domain/entity/closure_state.dart';
import 'package:tentura/features/closure/domain/silent_preview.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Live bars: what each member would get if the colleagues stay silent.
class ClosurePreview extends StatelessWidget {
  const ClosurePreview({required this.data, super.key});

  final ClosureState data;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final shares = silentPreview(
      outcomes: {for (final m in data.members) m.id: data.outcomes?[m.id]},
      split: data.split,
    );
    final top = shares.values.fold<double>(0, (a, b) => a > b ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.closureAuthorPreviewTitle,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: TenturaSpacing.row),
        for (final m in data.members)
          Padding(
            padding: const EdgeInsets.only(bottom: TenturaSpacing.row),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.displayName ?? m.id,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: TenturaSpacing.tight),
                FractionallySizedBox(
                  key: ValueKey('closure.author.preview.${m.id}'),
                  widthFactor: top == 0 ? 0 : (shares[m.id] ?? 0) / top,
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
