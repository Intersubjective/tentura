import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/features/home/ui/bloc/new_stuff_cubit.dart';

/// Keeps `NewStuffCubit.activeHomeTab` in sync with `TabsRouter.activeIndex`
/// (including non-tap navigations).
class HomeBottomNavListener extends StatefulWidget {
  const HomeBottomNavListener({
    required this.tabsRouter,
    required this.child,
    super.key,
  });

  final TabsRouter tabsRouter;
  final Widget child;

  @override
  State<HomeBottomNavListener> createState() => _HomeBottomNavListenerState();
}

class _HomeBottomNavListenerState extends State<HomeBottomNavListener> {
  @override
  void initState() {
    super.initState();
    widget.tabsRouter.addListener(_syncActiveTab);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncActiveTab());
  }

  @override
  void didUpdateWidget(covariant HomeBottomNavListener oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabsRouter != widget.tabsRouter) {
      oldWidget.tabsRouter.removeListener(_syncActiveTab);
      widget.tabsRouter.addListener(_syncActiveTab);
    }
    _syncActiveTab();
  }

  @override
  void dispose() {
    widget.tabsRouter.removeListener(_syncActiveTab);
    super.dispose();
  }

  void _syncActiveTab() {
    final cubit = GetIt.I<NewStuffCubit>();
    final oldTab = cubit.state.activeHomeTab;
    final newTab = HomeTabSpec.fromIndex(widget.tabsRouter.activeIndex)?.tab;
    if (newTab == null || oldTab == newTab) return;
    // Mark the tab the user is LEAVING as seen so its current max becomes the
    // baseline. The tab the user is ENTERING keeps its old baseline, letting
    // any newer activity appear as dots.
    switch (oldTab) {
      case HomeTab.work:
        unawaited(cubit.markMyWorkTabSeen());
      case HomeTab.inbox:
        unawaited(cubit.markInboxTabSeen());
      case HomeTab.network || HomeTab.me:
        break;
    }
    cubit.setActiveHomeTab(newTab);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
