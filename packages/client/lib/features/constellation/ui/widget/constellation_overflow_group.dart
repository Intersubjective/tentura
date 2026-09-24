import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/constellation_cubit.dart';

/// Measured size of [ConstellationOverflowGroup] for a [label] at the current
/// theme, tokens, and text scaler — matches the widget layout math.
Size constellationOverflowChipSize(BuildContext context, String label) {
  final tt = context.tt;
  final theme = Theme.of(context);
  final textScaler = MediaQuery.textScalerOf(context);
  final style = theme.textTheme.labelLarge;
  final textPainter = TextPainter(
    text: TextSpan(text: label, style: style),
    maxLines: 1,
    textDirection: Directionality.of(context),
    textScaler: textScaler,
  )..layout();
  final textWidth = textPainter.width;
  final textHeight = textPainter.height;
  final width =
      2 * tt.screenHPadding + tt.iconSize + tt.iconTextGap + textWidth;
  final height = math.max(tt.buttonHeight, textHeight + 2 * tt.tightGap);
  return Size(width, height);
}

/// Labelled expansion control for a person's request satellites hidden by the
/// label budget. A secondary tap on the author node may toggle the same state.
class ConstellationOverflowGroup extends StatelessWidget {
  const ConstellationOverflowGroup({
    required this.authorId,
    required this.authorName,
    required this.hiddenCount,
    super.key,
  });

  final String authorId;
  final String authorName;
  final int hiddenCount;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConstellationCubit, ConstellationState>(
      buildWhen: (previous, current) =>
          previous.composition != current.composition ||
          previous.graphRevision != current.graphRevision,
      builder: (context, state) => _buildChip(context),
    );
  }

  Widget _buildChip(BuildContext context) {
    final cubit = context.read<ConstellationCubit>();
    final expanded = cubit.isSatelliteOverflowExpanded(authorId);
    if (!expanded && hiddenCount <= 0) {
      return const SizedBox.shrink();
    }

    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final theme = Theme.of(context);
    final label = expanded
        ? l10n.constellationFewerRequests
        : l10n.constellationMoreRequests(hiddenCount);
    final semanticsLabel = expanded
        ? '${l10n.constellationFewerRequests}, $authorName'
        : l10n.constellationMoreRequestsByAuthor(hiddenCount, authorName);
    final chipSize = constellationOverflowChipSize(context, label);

    return Semantics(
      button: true,
      expanded: expanded,
      identifier: 'constellation.overflow.$authorId',
      label: semanticsLabel,
      child: SizedBox(
        key: Key('constellation.overflow.$authorId'),
        width: chipSize.width,
        height: chipSize.height,
        child: Material(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(tt.cardRadius),
          child: InkWell(
            onTap: () => cubit.toggleSatelliteOverflow(authorId),
            onSecondaryTap: () => cubit.toggleSatelliteOverflow(authorId),
            borderRadius: BorderRadius.circular(tt.cardRadius),
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
