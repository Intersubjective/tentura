import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_window_class.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../bloc/home_tab_reselect_cubit.dart';
import '../bloc/new_stuff_cubit.dart';
import '../widget/friends_navbar_item.dart';
import '../widget/home_bottom_nav_listener.dart';
import '../widget/inbox_navbar_item.dart';
import '../widget/my_work_navbar_item.dart';
import '../widget/profile_navbar_item.dart';

@RoutePage()
class HomeScreen extends StatelessWidget implements AutoRouteWrapper {
  const HomeScreen({super.key});

  static const _homeTabRoutes = [
    MyWorkRoute(),
    InboxRoute(),
    FriendsRoute(),
    ProfileRoute(),
  ];

  @override
  Widget wrappedRoute(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: GetIt.I<ScreenCubit>()),
      BlocProvider.value(value: GetIt.I<HomeTabReselectCubit>()),
      BlocProvider.value(value: GetIt.I<NewStuffCubit>()),
    ],
    child: this,
  );

  void _onDestinationSelected(
    BuildContext context,
    TabsRouter tabsRouter,
    int index,
  ) {
    final prev = tabsRouter.activeIndex;
    tabsRouter.setActiveIndex(index);
    if (index == prev) {
      final reselect = context.read<HomeTabReselectCubit>();
      if (index == 0) {
        reselect.bumpMyWorkReselect();
      } else if (index == 1) {
        reselect.bumpInboxReselect();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return BlocSelector<ProfileCubit, ProfileState, String>(
      bloc: GetIt.I<ProfileCubit>(),
      selector: (state) => state.profile.displayName,
      builder: (context, profileTitle) {
        // Fixed tab label keeps the profile icon stable; long names go to tooltip.
        final profileTooltipLabel = profileTitle.isEmpty
            ? l10n.noName
            : profileTitle;
        return LayoutBuilder(
          builder: (context, constraints) {
            final windowClass = windowClassForWidth(constraints.maxWidth);
            final useSideNav = windowClass != WindowClass.compact;
            return AutoTabsRouter(
              routes: _homeTabRoutes,
              transitionBuilder: (context, child, animation) => FadeTransition(
                opacity: animation,
                child: child,
              ),
              builder: (context, child) {
                final tabsRouter = context.tabsRouter;
                if (useSideNav) {
                  final extendedRail = windowClass == WindowClass.expanded;
                  return Scaffold(
                    resizeToAvoidBottomInset: false,
                    body: HomeBottomNavListener(
                      tabsRouter: tabsRouter,
                      child: Row(
                        children: [
                          NavigationRail(
                            extended: extendedRail,
                            selectedIndex: tabsRouter.activeIndex,
                            onDestinationSelected: (index) =>
                                _onDestinationSelected(
                                  context,
                                  tabsRouter,
                                  index,
                                ),
                            labelType: extendedRail
                                ? NavigationRailLabelType.none
                                : NavigationRailLabelType.all,
                            destinations: [
                              NavigationRailDestination(
                                icon: const MyWorkNavbarItem(),
                                selectedIcon: const MyWorkNavbarItem(
                                  selected: true,
                                ),
                                label: Text(l10n.myWork),
                              ),
                              NavigationRailDestination(
                                icon: const InboxNavbarItem(),
                                selectedIcon: const InboxNavbarItem(
                                  selected: true,
                                ),
                                label: Text(l10n.inbox),
                              ),
                              NavigationRailDestination(
                                icon: const FriendsNavbarItem(),
                                selectedIcon: const FriendsNavbarItem(
                                  selected: true,
                                ),
                                label: Text(l10n.network),
                              ),
                              NavigationRailDestination(
                                icon: Tooltip(
                                  message: profileTooltipLabel,
                                  child: const ProfileNavBarItem(),
                                ),
                                label: Text(l10n.profile),
                              ),
                            ],
                          ),
                          const VerticalDivider(width: 1, thickness: 1),
                          Expanded(child: child),
                        ],
                      ),
                    ),
                  );
                }
                return Scaffold(
                  resizeToAvoidBottomInset: false,
                  body: child,
                  bottomNavigationBar: HomeBottomNavListener(
                    tabsRouter: tabsRouter,
                    child: NavigationBar(
                      onDestinationSelected: (index) =>
                          _onDestinationSelected(context, tabsRouter, index),
                      selectedIndex: tabsRouter.activeIndex,
                      destinations: [
                        NavigationDestination(
                          icon: const MyWorkNavbarItem(),
                          selectedIcon: const MyWorkNavbarItem(selected: true),
                          label: l10n.myWork,
                        ),
                        NavigationDestination(
                          icon: const InboxNavbarItem(),
                          selectedIcon: const InboxNavbarItem(selected: true),
                          label: l10n.inbox,
                        ),
                        NavigationDestination(
                          icon: const FriendsNavbarItem(),
                          selectedIcon: const FriendsNavbarItem(
                            selected: true,
                          ),
                          label: l10n.network,
                        ),
                        NavigationDestination(
                          icon: const ProfileNavBarItem(),
                          label: l10n.profile,
                          tooltip: profileTooltipLabel,
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
