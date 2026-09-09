import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/constellation_cubit.dart';

/// Labelled expansion control for a person's request satellites hidden by the
/// label budget. A secondary tap on the author node may toggle the same state.
class ConstellationOverflowGroup extends StatelessWidget {
  const ConstellationOverflowGroup({
    required this.authorId,
    required this.hiddenCount,
    super.key,
  });

  final String authorId;
  final int hiddenCount;

  @override
  Widget build(BuildContext context) {
    if (hiddenCount <= 0) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final cubit = context.read<ConstellationCubit>();
    final expanded = cubit.isSatelliteOverflowExpanded(authorId);
    final label = l10n.constellationMoreRequests(hiddenCount);

    return Semantics(
      button: true,
      expanded: expanded,
      label: label,
      child: Material(
        key: Key('constellation.overflow.$authorId'),
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(tt.cardRadius),
        child: InkWell(
          onTap: () => cubit.toggleSatelliteOverflow(authorId),
          onSecondaryTap: () => cubit.toggleSatelliteOverflow(authorId),
          borderRadius: BorderRadius.circular(tt.cardRadius),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: tt.buttonHeight,
              minWidth: tt.buttonHeight,
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tt.screenHPadding,
                vertical: tt.tightGap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: tt.iconSize,
                    color: theme.colorScheme.primary,
                  ),
                  SizedBox(width: tt.iconTextGap),
                  Flexible(
                    child: Text(
                      label,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
