import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../bloc/constellation_cubit.dart';
import 'constellation_arrange_sheet.dart';

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

  /// Viewport insets passed to [ConstellationCubit.fitWholeField] /
  /// [ConstellationCubit.centerOnEgo], excluding this control column and any
  /// open context-panel chrome (person or request).
  static EdgeInsets cameraViewportInsets(
    BuildContext context, {
    required bool contextPanelVisible,
  }) {
    final tt = context.tt;
    final media = MediaQuery.of(context);
    final padding = media.padding;

    final controlColumnHeight = tt.buttonHeight * 2 + tt.tightGap * 2;
    final top = padding.top + tt.rowGap + controlColumnHeight;
    var right = padding.right + tt.screenHPadding + tt.buttonHeight;
    var bottom = padding.bottom;

    if (contextPanelVisible && context.windowClass == WindowClass.compact) {
      bottom +=
          media.size.height * tt.graphPersonContextCompactMaxHeightFraction +
          tt.rowGap * 2;
    }
    if (contextPanelVisible && context.windowClass != WindowClass.compact) {
      right += tt.graphPersonContextWidth + tt.screenHPadding;
    }

    return EdgeInsets.only(top: top, right: right, bottom: bottom);
  }

  /// «Сбросить позиции» (#251), behind a confirmation.
  Future<void> _confirmReset(BuildContext context) async {
    final l10n = L10n.of(context)!;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final confirmed = await TenturaConfirmDialog.show(
      context: context,
      title: l10n.constellationResetPositionsTitle,
      content: l10n.constellationResetPositionsBody,
      confirmLabel: l10n.constellationResetPositionsConfirm,
    );
    if (confirmed != true) {
      return;
    }
    if (!await cubit.resetAllPositions()) {
      messenger?.showSnackBar(
        SnackBar(content: Text(l10n.constellationResetPositionsFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;

    return BlocBuilder<ConstellationCubit, ConstellationState>(
      buildWhen: (previous, current) =>
          previous.placementPhase != current.placementPhase ||
          previous.hasUserPlacements != current.hasUserPlacements,
      builder: (context, state) {
        final enabled =
            state.placementPhase == ConstellationPlacementPhase.idle;
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
              if (!tagViewActive) ...[
                SizedBox(height: tt.tightGap * 2),
                IconButton.filledTonal(
                  key: const Key('constellation.camera.arrange'),
                  tooltip: l10n.constellationArrange,
                  onPressed: enabled
                      ? () => showConstellationArrangeSheet(
                          context,
                          cubit: cubit,
                        )
                      : null,
                  icon: const Icon(Icons.tune),
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
