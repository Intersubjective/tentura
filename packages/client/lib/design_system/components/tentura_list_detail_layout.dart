import 'package:flutter/material.dart';

import '../tentura_spacing.dart';
import 'tentura_vertical_hairline.dart';

/// Material 3 canonical "list-detail" layout for a detail route.
///
/// The detail stays a real route (its URL, browser Back and deep links are
/// unchanged); when the body is wide enough, the list it was opened from sits
/// beside it in a fixed 360 dp pane, so choosing another item does not mean
/// going back first. Narrower, only the detail shows — the compact behaviour.
///
/// The detail gets whatever width is left and lays itself out for it (a
/// [TenturaSupportingPaneScope] inside it measures its own pane).
class TenturaListDetailLayout extends StatelessWidget {
  const TenturaListDetailLayout({
    required this.detail,
    this.list,
    super.key,
  });

  static const listPaneKey = Key('tentura-list-detail-list-pane');

  /// The source list, or null when the detail was not opened from one.
  final Widget? list;

  final Widget detail;

  @override
  Widget build(BuildContext context) {
    final list = this.list;
    if (list == null) return detail;
    return LayoutBuilder(
      builder: (context, constraints) {
        final fits =
            constraints.maxWidth >=
            TenturaSpacing.supportingPaneWidth +
                TenturaSpacing.supportingPrimaryMinWidth;
        if (!fits) return detail;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: listPaneKey,
              width: TenturaSpacing.supportingPaneWidth,
              child: list,
            ),
            const TenturaVerticalHairline(),
            Expanded(child: detail),
          ],
        );
      },
    );
  }
}

/// The item a list-detail pane is showing, so the list can mark it selected.
class TenturaListDetailSelection extends InheritedWidget {
  const TenturaListDetailSelection({
    required this.selectedId,
    required super.child,
    super.key,
  });

  final String selectedId;

  static String? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<TenturaListDetailSelection>()
      ?.selectedId;

  @override
  bool updateShouldNotify(TenturaListDetailSelection oldWidget) =>
      oldWidget.selectedId != selectedId;
}
