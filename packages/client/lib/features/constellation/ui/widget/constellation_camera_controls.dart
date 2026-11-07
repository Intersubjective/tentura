import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/ui_utils.dart' show showSnackBar;

import '../bloc/constellation_cubit.dart';
import '../bloc/constellation_selection_cubit.dart';

/// Floating camera recovery actions for the Constellation map (UI-08).
class ConstellationCameraControls extends StatelessWidget {
  const ConstellationCameraControls({
    required this.cubit,
    required this.viewportInsets,
    this.arrangeV2Enabled = false,
    this.tagViewActive = false,
    super.key,
  });

  final ConstellationCubit cubit;
  final EdgeInsets viewportInsets;

  /// The Arrange sheet replaces the Rearrange and Reset buttons.
  final bool arrangeV2Enabled;

  /// The Arrange sheet is not offered in the tag view.
  final bool tagViewActive;

  /// «Сбросить позиции» (#251), behind a confirmation.
  Future<void> _confirmReset(BuildContext context) async {
    final l10n = L10n.of(context)!;
    final confirmed = await TenturaConfirmDialog.show(
      context: context,
      title: l10n.constellationResetPositionsTitle,
      content: l10n.constellationResetPositionsBody,
      confirmLabel: l10n.constellationResetPositionsConfirm,
    );
    if (confirmed != true) {
      return;
    }
    if (!await cubit.resetAllPositions() && context.mounted) {
      showSnackBar(context, text: l10n.constellationResetPositionsFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;

    return BlocBuilder<ConstellationCubit, ConstellationState>(
      buildWhen: (previous, current) =>
          previous.placementPhase != current.placementPhase ||
          previous.hasUserPlacements != current.hasUserPlacements ||
          previous.composition != current.composition ||
          previous.visibility != current.visibility,
      builder: (context, state) {
        final enabled =
            state.placementPhase == ConstellationPlacementPhase.idle;
        final canArrange = cubit.canArrange;
        final arranging =
            maybeConstellationSelection(context)?.state.arranging ?? false;
        final buttonSize = BoxConstraints.tightFor(
          width: tt.buttonHeight,
          height: tt.buttonHeight,
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton.filledTonal(
              key: TestIds.key(TestIds.constellationFitAll),
              tooltip: l10n.constellationFitAll,
              onPressed: enabled
                  ? () => cubit.fitWholeField(insets: viewportInsets)
                  : null,
              icon: const Icon(Icons.fit_screen),
              constraints: buttonSize,
            ),
            SizedBox(height: tt.tightGap * 2),
            IconButton.filledTonal(
              key: TestIds.key(TestIds.constellationCenterOnMe),
              tooltip: l10n.graphCenterView,
              onPressed: enabled
                  ? () => cubit.centerOnEgo(insets: viewportInsets)
                  : null,
              icon: const Icon(Icons.my_location),
              constraints: buttonSize,
            ),
            if (arrangeV2Enabled) ...[
              if (canArrange && !tagViewActive) ...[
                SizedBox(height: tt.tightGap * 2),
                IconButton.filledTonal(
                  key: const Key('constellation.camera.arrange'),
                  tooltip: l10n.constellationArrangingTitle,
                  isSelected: arranging,
                  onPressed: enabled
                      ? () => maybeConstellationSelection(
                          context,
                        )?.enterArranging()
                      : null,
                  // open_with reads as move/reposition; keep Filters on tune (#1036).
                  icon: const Icon(Icons.open_with),
                  constraints: buttonSize,
                ),
              ],
            ] else if (state.hasUserPlacements) ...[
              SizedBox(height: tt.tightGap * 2),
              // The icon's label names the button; the tooltip is visual
              // only, so it is not read twice (#678).
              Tooltip(
                message: l10n.constellationRearrange,
                excludeFromSemantics: true,
                child: IconButton.filledTonal(
                  key: TestIds.key(TestIds.constellationRearrange),
                  onPressed: enabled ? cubit.rearrangeFreeNodes : null,
                  icon: Icon(
                    Icons.auto_fix_high,
                    semanticLabel: l10n.constellationRearrange,
                  ),
                  constraints: buttonSize,
                ),
              ),
              SizedBox(height: tt.tightGap * 2),
              Tooltip(
                message: l10n.constellationResetPositions,
                excludeFromSemantics: true,
                child: IconButton.filledTonal(
                  key: const Key('constellation.camera.reset_positions'),
                  onPressed: enabled ? () => _confirmReset(context) : null,
                  icon: Icon(
                    Icons.restart_alt,
                    semanticLabel: l10n.constellationResetPositions,
                  ),
                  constraints: buttonSize,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
