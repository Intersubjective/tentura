import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/constellation_cubit.dart';

Future<void> showConstellationArrangeSheet(
  BuildContext context, {
  required ConstellationCubit cubit,
}) => showTenturaAdaptiveSheet<void>(
  context: context,
  builder: (_) => ConstellationArrangeSheet(cubit: cubit),
);

/// The Field's Arrange menu: undo / redo of arrangement actions, re-arrange
/// and an immediate, undoable reset of every placed position.
class ConstellationArrangeSheet extends StatelessWidget {
  const ConstellationArrangeSheet({required this.cubit, super.key});

  final ConstellationCubit cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    final enabled =
        cubit.state.placementPhase == ConstellationPlacementPhase.idle;

    VoidCallback? close(bool available, VoidCallback action) =>
        available && enabled
        ? () {
            navigator.pop();
            action();
          }
        : null;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: tt.screenHPadding,
          right: tt.screenHPadding,
          bottom: tt.rowGap,
        ),
        child: TenturaMenuGroup(
          title: l10n.constellationArrange,
          children: [
            TenturaMenuTile(
              icon: Icons.undo,
              title: l10n.constellationUndo,
              opensPage: false,
              onTap: close(
                cubit.canUndoArrangement,
                cubit.undoArrangement,
              ),
            ),
            TenturaMenuTile(
              icon: Icons.redo,
              title: l10n.constellationRedo,
              opensPage: false,
              onTap: close(
                cubit.canRedoArrangement,
                cubit.redoArrangement,
              ),
            ),
            TenturaMenuTile(
              icon: Icons.auto_fix_high,
              title: l10n.constellationRearrange,
              opensPage: false,
              onTap: close(true, cubit.rearrangeFreeNodes),
            ),
            TenturaMenuTile(
              icon: Icons.shuffle,
              title: l10n.constellationRearrangeEveryone,
              opensPage: false,
              onTap: close(true, cubit.previewRearrangeAll),
            ),
            TenturaMenuTile(
              icon: Icons.restart_alt,
              title: l10n.constellationResetPositions,
              opensPage: false,
              onTap: close(true, () async {
                if (!await cubit.resetAllPositions(saveHistory: true)) {
                  messenger?.showSnackBar(
                    SnackBar(
                      content: Text(l10n.constellationResetPositionsFailed),
                    ),
                  );
                }
              }),
            ),
          ],
        ),
      ),
    );
  }
}
