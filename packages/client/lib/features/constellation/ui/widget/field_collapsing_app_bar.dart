import 'package:flutter/material.dart';

/// Matches the compact context sheet snap duration (250 ms, same as the overlay).
const kFieldContextSheetSnapDuration = Duration(milliseconds: 250);

/// On compact Field widths, hides the top app bar while the map context sheet
/// is expanded so the map gains roughly one toolbar of height (#974).
class FieldCollapsingAppBar extends StatelessWidget
    implements PreferredSizeWidget {
  const FieldCollapsingAppBar({
    required this.collapsed,
    required this.bar,
    super.key,
  });

  final bool collapsed;
  final PreferredSizeWidget bar;

  @override
  Size get preferredSize => Size.fromHeight(
    collapsed ? 0 : bar.preferredSize.height,
  );

  @override
  Widget build(BuildContext context) {
    final target = collapsed ? 0.0 : bar.preferredSize.height;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : kFieldContextSheetSnapDuration;
    return AnimatedContainer(
      key: ValueKey<bool>(collapsed),
      duration: duration,
      curve: Curves.easeOutCubic,
      height: target,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: TickerMode(enabled: !collapsed, child: bar),
    );
  }
}
