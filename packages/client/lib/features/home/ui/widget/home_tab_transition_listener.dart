import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';

import 'package:tentura/ui/navigation/home_tab.dart';

/// Fires [onEnter] when [tab] becomes active and [onLeave] when it stops being
/// active — whether from another bottom-nav tab or a URL change on the shell.
class HomeTabTransitionListener extends StatefulWidget {
  const HomeTabTransitionListener({
    required this.tabsRouter,
    required this.tab,
    required this.child,
    this.onEnter,
    this.onLeave,
    super.key,
  });

  final TabsRouter tabsRouter;
  final HomeTab tab;
  final Widget child;
  final VoidCallback? onEnter;
  final VoidCallback? onLeave;

  @override
  State<HomeTabTransitionListener> createState() =>
      _HomeTabTransitionListenerState();
}

class _HomeTabTransitionListenerState extends State<HomeTabTransitionListener> {
  late int _lastIndex;

  int get _tabIndex => HomeTabSpec.forTab(widget.tab).index;

  @override
  void initState() {
    super.initState();
    _lastIndex = widget.tabsRouter.activeIndex;
    widget.tabsRouter.addListener(_onTabsChanged);
  }

  @override
  void didUpdateWidget(HomeTabTransitionListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabsRouter != widget.tabsRouter) {
      oldWidget.tabsRouter.removeListener(_onTabsChanged);
      widget.tabsRouter.addListener(_onTabsChanged);
      _lastIndex = widget.tabsRouter.activeIndex;
    }
  }

  @override
  void dispose() {
    widget.tabsRouter.removeListener(_onTabsChanged);
    super.dispose();
  }

  void _onTabsChanged() {
    final index = widget.tabsRouter.activeIndex;
    final wasOnTab = _lastIndex == _tabIndex;
    final nowOnTab = index == _tabIndex;
    _lastIndex = index;
    if (!mounted) return;
    if (wasOnTab && !nowOnTab) {
      widget.onLeave?.call();
    }
    if (!wasOnTab && nowOnTab) {
      widget.onEnter?.call();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
