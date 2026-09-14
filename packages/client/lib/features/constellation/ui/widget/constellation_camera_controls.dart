import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../bloc/constellation_cubit.dart';

/// Floating camera recovery actions for the Constellation map (UI-08).
class ConstellationCameraControls extends StatelessWidget {
  const ConstellationCameraControls({
    required this.cubit,
    required this.viewportInsets,
    super.key,
  });

  final ConstellationCubit cubit;
  final EdgeInsets viewportInsets;

  /// Viewport insets passed to [ConstellationCubit.fitWholeField] /
  /// [ConstellationCubit.centerOnEgo], excluding this control column and any
  /// open person-context chrome.
  static EdgeInsets cameraViewportInsets(
    BuildContext context, {
    required bool personPanelVisible,
  }) {
    final tt = context.tt;
    final media = MediaQuery.of(context);
    final padding = media.padding;

    final controlColumnHeight = tt.buttonHeight * 2 + tt.tightGap * 2;
    final top = padding.top + tt.rowGap + controlColumnHeight;
    var right = padding.right + tt.screenHPadding + tt.buttonHeight;
    var bottom = padding.bottom;

    if (personPanelVisible && context.windowClass == WindowClass.compact) {
      bottom +=
          media.size.height * tt.graphPersonContextCompactMaxHeightFraction +
          tt.rowGap * 2;
    }
    if (personPanelVisible && context.windowClass != WindowClass.compact) {
      right += tt.graphPersonContextWidth + tt.screenHPadding;
    }

    return EdgeInsets.only(top: top, right: right, bottom: bottom);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;

    return BlocBuilder<ConstellationCubit, ConstellationState>(
      buildWhen: (previous, current) =>
          previous.placementPhase != current.placementPhase,
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
          ],
        );
      },
    );
  }
}
