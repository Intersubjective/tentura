import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/ui/navigation/home_tab.dart';
import 'package:tentura/features/home/ui/widget/home_tab_transition_listener.dart';

import '../bloc/my_work_cubit.dart';

/// #491: coming back to the Requests tab from another tab — a tab tap or a
/// `#/home/work` URL — opens on Active work instead of the Archived filter
/// left from the last visit (which reads as lost requests). The sort and
/// every other filter are kept; returning from a pushed request page does
/// not change the active tab, so it keeps Archived too.
class MyWorkTabReentryListener extends StatelessWidget {
  const MyWorkTabReentryListener({
    required this.tabsRouter,
    required this.child,
    super.key,
  });

  final TabsRouter tabsRouter;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return HomeTabTransitionListener(
      tabsRouter: tabsRouter,
      tab: HomeTab.work,
      onEnter: () {
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
      },
      child: child,
    );
  }
}
