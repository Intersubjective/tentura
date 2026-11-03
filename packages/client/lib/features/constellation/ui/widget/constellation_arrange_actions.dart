import 'package:flutter/material.dart';

import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/constellation_cubit.dart';
import 'constellation_layout_history_sheet.dart';
import 'constellation_tidied_snack_bar.dart';

/// Shared Arrange actions for the overflow menu (#938 toolbar ⋯).
class ConstellationArrangeActions {
  ConstellationArrangeActions._();

  static Future<void> showOverflowMenu(
    BuildContext context, {
    required ConstellationCubit cubit,
  }) => showTenturaAdaptiveSheet<void>(
    context: context,
    builder: (_) => _ConstellationArrangeOverflowMenu(cubit: cubit),
  );
}

class _ConstellationArrangeOverflowMenu extends StatelessWidget {
  const _ConstellationArrangeOverflowMenu({required this.cubit});

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
        child: SingleChildScrollView(
          child: TenturaMenuGroup(
            title: l10n.constellationArrange,
            children: [
              TenturaMenuTile(
                icon: Icons.favorite_outline,
                title: l10n.constellationSaveFavourite,
                opensPage: false,
                onTap: close(true, cubit.saveFavouriteLayout),
              ),
              TenturaMenuTile(
                icon: Icons.restore,
                title: l10n.constellationRestoreFavourite,
                opensPage: false,
                onTap: close(true, cubit.restoreFavouriteLayout),
              ),
              TenturaMenuTile(
                icon: Icons.history,
                title: l10n.constellationLayoutHistory,
                onTap: close(
                  true,
                  () => showConstellationLayoutHistorySheet(
                    navigator.context,
                    cubit: cubit,
                  ),
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
                  final snackbarContext = messenger?.context;
                  if (!await cubit.resetAllPositions(saveHistory: true) &&
                      snackbarContext != null &&
                      snackbarContext.mounted) {
                    showSnackBar(
                      snackbarContext,
                      text: l10n.constellationResetPositionsFailed,
                      isError: true,
                    );
                  }
                }),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// @deprecated Use [ConstellationArrangeActions.showOverflowMenu] from the
/// arranging toolbar. Kept as a thin redirect for any stale call sites.
Future<void> showConstellationArrangeSheet(
  BuildContext context, {
  required ConstellationCubit cubit,
}) => ConstellationArrangeActions.showOverflowMenu(context, cubit: cubit);
