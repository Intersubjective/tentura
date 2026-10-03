import 'package:flutter/material.dart';

import '../tentura_tokens.dart';

class TenturaPrimaryTabBar extends StatelessWidget
    implements PreferredSizeWidget {
  const TenturaPrimaryTabBar({
    required this.tabs,
    this.controller,
    this.isScrollable = true,
    this.labelPadding,
    super.key,
  });

  final List<Widget> tabs;
  final TabController? controller;
  final bool isScrollable;
  final EdgeInsetsGeometry? labelPadding;

  @override
  Size get preferredSize => const Size.fromHeight(kTextTabBarHeight);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // Tab-root bars render on surface (see [TenturaTopBarTone.primary]):
    // brand marks the selection, muted ink the rest.
    final selected = scheme.primary;
    final unselected = scheme.onSurfaceVariant;

    return TabBar(
      controller: controller,
      automaticIndicatorColorAdjustment: false,
      tabAlignment: TabAlignment.start,
      isScrollable: isScrollable,
      labelPadding:
          labelPadding ?? EdgeInsets.symmetric(horizontal: context.tt.rowGap),
      labelColor: selected,
      unselectedLabelColor: unselected,
      indicatorColor: selected,
      dividerColor: Colors.transparent,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w600,
        color: selected,
      ),
      unselectedLabelStyle: theme.textTheme.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
        color: unselected,
      ),
      tabs: tabs,
    );
  }
}
