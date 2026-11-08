import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/constellation_cubit.dart';
import '../bloc/constellation_selection_cubit.dart';
import 'constellation_arrange_actions.dart';
import 'constellation_selection_layers.dart';
import 'constellation_tidied_snack_bar.dart';

/// Field «Arranging» toolbar (#938); default top chrome on the map body.
class ConstellationArrangingToolbar extends StatelessWidget {
  const ConstellationArrangingToolbar({
    required this.cubit,
    this.peopleTagsEnabled = true,
    this.topEmbedded = false,
    super.key,
  });

  final ConstellationCubit cubit;
  final bool peopleTagsEnabled;

  /// Rendered in the capped top chrome row instead of the bottom map overlay.
  final bool topEmbedded;

  @override
  Widget build(BuildContext context) {
    final selection = maybeConstellationSelection(context);
    if (selection == null) return const SizedBox.shrink();
    return BlocBuilder<
      ConstellationSelectionCubit,
      ConstellationMultiSelection
    >(
      bloc: selection,
      builder: (context, state) {
        if (!state.arranging || cubit.state.isComposing) {
          return const SizedBox.shrink();
        }
        final tt = context.tt;
        final l10n = L10n.of(context)!;
        final theme = Theme.of(context);
        final enabled =
            cubit.state.placementPhase == ConstellationPlacementPhase.idle;
        final showSelectionRow = !state.isEmpty || state.sector != null;
        final outerPadding = topEmbedded
            ? EdgeInsets.symmetric(
                horizontal: tt.screenHPadding,
                vertical: tt.tightGap,
              )
            : EdgeInsets.all(tt.rowGap);
        final inner = DecoratedBox(
          key: const Key('constellation.arranging.toolbar'),
          decoration: topEmbedded
              ? const BoxDecoration()
              : BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(tt.cardRadius),
                  boxShadow: [
                    BoxShadow(
                      color: theme.shadowColor.withValues(alpha: 0.18),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: topEmbedded ? 0 : tt.screenHPadding,
              vertical: tt.tightGap,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (showSelectionRow)
                  ConstellationSelectionBar(
                    cubit: cubit,
                    peopleTagsEnabled: peopleTagsEnabled,
                    arrangingEmbedded: true,
                  )
                else
                  _mainToolbarRow(
                    context,
                    cubit: cubit,
                    selection: selection,
                    enabled: enabled,
                  ),
                if (!topEmbedded)
                  ListenableBuilder(
                    listenable: RendererBinding.instance.mouseTracker,
                    builder: (context, _) {
                      final mouse = RendererBinding
                          .instance
                          .mouseTracker
                          .mouseIsConnected;
                      return Padding(
                        padding: EdgeInsets.only(top: tt.tightGap),
                        child: Text(
                          mouse
                              ? l10n.constellationArrangingHintMouse
                              : l10n.constellationArrangingHintTouch,
                          key: const Key(
                            'constellation.arranging.hint',
                          ),
                          style: theme.textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
        if (topEmbedded) {
          return Padding(padding: outerPadding, child: inner);
        }
        return Padding(
          padding: outerPadding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: TenturaSpacing.listPaneWidth,
              ),
              child: inner,
            ),
          ),
        );
      },
    );
  }

  Widget _mainToolbarRow(
    BuildContext context, {
    required ConstellationCubit cubit,
    required ConstellationSelectionCubit selection,
    required bool enabled,
  }) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: tt.tightGap,
      runSpacing: tt.tightGap,
      children: [
        IconButton(
          key: const Key('constellation.arranging.undo'),
          tooltip: l10n.constellationUndo,
          onPressed: enabled && cubit.canUndoArrangement
              ? () => unawaited(cubit.undoArrangement())
              : null,
          icon: const Icon(Icons.undo),
        ),
        IconButton(
          key: const Key('constellation.arranging.redo'),
          tooltip: l10n.constellationRedo,
          onPressed: enabled && cubit.canRedoArrangement
              ? () => unawaited(cubit.redoArrangement())
              : null,
          icon: const Icon(Icons.redo),
        ),
        TextButton.icon(
          key: const Key('constellation.arranging.tidy'),
          onPressed: enabled
              ? () async {
                  final count = await cubit.tidyUp();
                  if (count > 0 && context.mounted) {
                    showConstellationTidiedSnackBar(
                      context,
                      count: count,
                      onUndo: cubit.undoArrangement,
                    );
                  }
                }
              : null,
          icon: const Icon(Icons.auto_fix_high),
          label: Text(l10n.constellationTidyUp),
        ),
        TextButton.icon(
          key: const Key('constellation.arranging.select'),
          onPressed: enabled
              ? () => selection.setSelecting(!selection.state.selecting)
              : null,
          icon: Icon(
            Icons.crop_square,
            color: selection.state.selecting
                ? Theme.of(context).colorScheme.primary
                : null,
          ),
          label: Text(l10n.constellationArrangingSelect),
        ),
        IconButton(
          key: const Key('constellation.arranging.more'),
          tooltip: l10n.constellationArrangingMoreActions,
          onPressed: enabled
              ? () => ConstellationArrangeActions.showOverflowMenu(
                  context,
                  cubit: cubit,
                )
              : null,
          icon: Icon(
            Icons.more_horiz,
            semanticLabel: l10n.constellationArrangingMoreActions,
          ),
        ),
      ],
    );
  }
}
