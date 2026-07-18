import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

/// Compact home tab bar with a **fixed** icon + label slot per destination.
///
/// Material [NavigationBar] positions each icon using that destination's label
/// height, so a wrapping RU label lifts its icon (and neighbors look uneven).
/// This bar keeps a one-line label slot so all five tabs share the same
/// vertical rhythm on narrow phones.
class HomeBottomNavigationBar extends StatelessWidget {
  const HomeBottomNavigationBar({
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<HomeNavDestination> destinations;

  /// Matches Material 3 [NavigationIndicator] defaults.
  static const double _indicatorWidth = 64;
  static const double _indicatorHeight = 32;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final navTheme = NavigationBarTheme.of(context);
    final scheme = theme.colorScheme;
    final tokens = context.tt;
    final height = navTheme.height ?? tokens.bottomNavHeight;

    final isDark = scheme.brightness == Brightness.dark;
    final indicatorColor =
        navTheme.indicatorColor ??
        (isDark ? scheme.secondaryContainer : scheme.primary);
    final selectedIconTheme =
        navTheme.iconTheme?.resolve(const {WidgetState.selected}) ??
        IconThemeData(
          size: 24,
          color: isDark ? scheme.onSecondaryContainer : scheme.onPrimary,
        );
    final unselectedIconTheme =
        navTheme.iconTheme?.resolve(const {}) ??
        IconThemeData(
          size: 24,
          color: scheme.onSurfaceVariant,
        );

    return Material(
      color: navTheme.backgroundColor ?? scheme.surfaceContainer,
      elevation: navTheme.elevation ?? 0,
      shadowColor: navTheme.shadowColor,
      surfaceTintColor: navTheme.surfaceTintColor ?? Colors.transparent,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: height,
          child: Semantics(
            explicitChildNodes: true,
            container: true,
            child: Row(
              children: [
                for (var i = 0; i < destinations.length; i++)
                  Expanded(
                    child: _HomeNavTile(
                      destination: destinations[i],
                      selected: i == selectedIndex,
                      indicatorColor: indicatorColor,
                      selectedIconTheme: selectedIconTheme,
                      unselectedIconTheme: unselectedIconTheme,
                      labelGap: tokens.tightGap,
                      onTap: () => onDestinationSelected(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class HomeNavDestination {
  const HomeNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.tooltip,
  });

  final Widget icon;
  final Widget selectedIcon;
  final String label;
  final String? tooltip;
}

class _HomeNavTile extends StatelessWidget {
  const _HomeNavTile({
    required this.destination,
    required this.selected,
    required this.indicatorColor,
    required this.selectedIconTheme,
    required this.unselectedIconTheme,
    required this.labelGap,
    required this.onTap,
  });

  final HomeNavDestination destination;
  final bool selected;
  final Color indicatorColor;
  final IconThemeData selectedIconTheme;
  final IconThemeData unselectedIconTheme;
  final double labelGap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final labelColor = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    final labelStyle = TenturaText.navLabel(labelColor).copyWith(
      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
    );
    final tooltip = destination.tooltip ?? destination.label;

    final tile = Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: HomeBottomNavigationBar._indicatorWidth,
              height: HomeBottomNavigationBar._indicatorHeight,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedOpacity(
                    opacity: selected ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: indicatorColor,
                        shape: const StadiumBorder(),
                      ),
                      child: const SizedBox(
                        width: HomeBottomNavigationBar._indicatorWidth,
                        height: HomeBottomNavigationBar._indicatorHeight,
                      ),
                    ),
                  ),
                  IconTheme(
                    data: selected ? selectedIconTheme : unselectedIconTheme,
                    child: selected
                        ? destination.selectedIcon
                        : destination.icon,
                  ),
                ],
              ),
            ),
            SizedBox(height: labelGap),
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Text(
                destination.label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: labelStyle,
              ),
            ),
          ],
        ),
      ),
    );

    if (tooltip.isEmpty) {
      return tile;
    }
    return Tooltip(message: tooltip, child: tile);
  }
}
