import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';

import 'package:tentura/app/router/home_tab_branches.dart';

import '../bloc/my_work_cubit.dart';

/// #491: coming back to the Requests tab from another tab — a tab tap or a
/// `#/home/work` URL — opens on Active work instead of the Archived filter
/// left from the last visit (which reads as lost requests). The sort and
/// every other filter are kept; returning from a pushed request page does
/// not change the active tab, so it keeps Archived too.
class MyWorkTabReentryListener extends StatefulWidget {
  const MyWorkTabReentryListener({
    required this.tabsRouter,
    required this.child,
    super.key,
  });

  final TabsRouter tabsRouter;
  final Widget child;

  @override
  State<MyWorkTabReentryListener> createState() =>
      _MyWorkTabReentryListenerState();
}

class _MyWorkTabReentryListenerState extends State<MyWorkTabReentryListener> {
  static final _workIndex = HomeTabSpec.forTab(HomeTab.work).index;

  late int _lastIndex;

  @override
  void initState() {
    super.initState();
    _lastIndex = widget.tabsRouter.activeIndex;
    widget.tabsRouter.addListener(_onTabsChanged);
  }

  @override
  void didUpdateWidget(MyWorkTabReentryListener oldWidget) {
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
    final reentered = index == _workIndex && _lastIndex != _workIndex;
    _lastIndex = index;
    if (!reentered || !mounted) return;
    final MyWorkCubit cubit;
    try {
      cubit = context.read<MyWorkCubit>();
    } on ProviderNotFoundException {
      // Signed-out shell: no account-scoped Requests list to reset.
      return;
    }
    if (cubit.state.filter == MyWorkFilter.archived) {
      cubit.setFilter(MyWorkFilter.active);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
