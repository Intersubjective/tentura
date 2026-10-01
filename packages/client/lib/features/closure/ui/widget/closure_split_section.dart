import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/closure/ui/bloc/closure_author_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Author split: locked until «Изменить распределение», then one slider per
/// member of set A (steps of 5, min 5, total 100).
class ClosureSplitSection extends StatelessWidget {
  const ClosureSplitSection({required this.state, super.key});

  final ClosureAuthorState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final cubit = context.read<ClosureAuthorCubit>();
    final data = state.data!;
    final draft = state.draft;
    final names = {for (final m in data.members) m.id: m.displayName ?? m.id};
    final hasSplit = data.split != null;

    final resetButton = hasSplit
        ? TextButton(
            onPressed: cubit.resetSplit,
            child: Text(l10n.closureAuthorSplitReset),
          )
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.closureAuthorSplitTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: TenturaSpacing.row),
        if (!state.splitAvailable)
          Text(l10n.closureAuthorSplitTooMany, style: theme.textTheme.bodySmall)
        else if (draft != null) ...[
          for (final e in draft.entries)
            _SplitSlider(
              name: names[e.key] ?? e.key,
              value: e.value,
              count: draft.length,
              onChanged: (v) => cubit.changeDraft(e.key, v),
            ),
          Wrap(
            spacing: TenturaSpacing.row,
            children: [
              FilledButton(
                key: const ValueKey('closure.author.split.save'),
                onPressed: cubit.saveSplit,
                child: Text(l10n.closureAuthorSplitSave),
              ),
              ?resetButton,
            ],
          ),
        ] else if (!hasSplit)
          Text(
            l10n.closureAuthorSplitEqual,
            style: theme.textTheme.bodySmall,
          )
        else
          for (final e in data.split!.entries)
            Text(
              l10n.closureAuthorSplitShare(names[e.key] ?? e.key, e.value),
              style: theme.textTheme.bodyMedium,
            ),
        if (draft == null) ...[
          const SizedBox(height: TenturaSpacing.row),
          Wrap(
            spacing: TenturaSpacing.row,
            children: [
              OutlinedButton(
                onPressed: state.splitAvailable ? cubit.unlockSplit : null,
                child: Text(l10n.closureAuthorSplitChange),
              ),
              ?resetButton,
            ],
          ),
        ],
      ],
    );
  }
}

class _SplitSlider extends StatelessWidget {
  const _SplitSlider({
    required this.name,
    required this.value,
    required this.count,
    required this.onChanged,
  });

  final String name;
  final int value;
  final int count;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const min = kClosureSplitStep;
    final max = 100 - kClosureSplitStep * (count - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                name,
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text('$value%', style: theme.textTheme.labelLarge),
          ],
        ),
        Slider(
          value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: (max - min) ~/ kClosureSplitStep,
          label: '$value%',
          semanticFormatterCallback: (v) => '$name ${v.round()}%',
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }
}
