import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

import '../../domain/constellation_minimap.dart';

/// Viewport insets passed to `ConstellationCubit.fitWholeField` /
/// `ConstellationCubit.centerOnEgo`, excluding the camera control column
/// (`ConstellationCameraControls`) and any
/// open context-panel chrome (person or request).
///
/// FCP §C (1055 U2): one formula for every camera op — bottomChromeHeight
/// is the measured tag lens + arranging + selection column; when the minimap
/// is expanded, reserve `minimapBlock`; bottom inset uses the larger of the two
/// plus safe-area padding and optional compact sheet.
EdgeInsets constellationCameraViewportInsets(
  BuildContext context, {
  required bool contextPanelVisible,
  double compactSheetHeight = 0,
  double bottomChromeHeight = 0,
  bool minimapExpanded = false,
}) {
  final tt = context.tt;
  final media = MediaQuery.of(context);
  final padding = media.padding;

  final top = padding.top + tt.rowGap;
  // Fit/recenter use this as the graph's safe viewport. The FAB column is
  // [screenHPadding + buttonHeight] wide from the trailing edge; without an
  // extra margin the usable rect ends exactly at the column's inner edge, so
  // labels and badges can sit under the buttons on narrow phones (#1034).
  var right = padding.right + tt.screenHPadding + tt.buttonHeight + tt.rowGap;
  final minimapBlock = minimapExpanded
      ? tt.buttonHeight +
            tt.tightGap * 2 +
            kConstellationMinimapSize +
            tt.rowGap * 2
      : 0.0;
  var bottom = padding.bottom + math.max(bottomChromeHeight, minimapBlock);

  if (contextPanelVisible && context.windowClass == WindowClass.compact) {
    bottom += compactSheetHeight + tt.sectionGap;
  }
  if (contextPanelVisible && context.windowClass != WindowClass.compact) {
    right += tt.graphPersonContextWidth + tt.screenHPadding;
  }

  return EdgeInsets.only(top: top, right: right, bottom: bottom);
}
