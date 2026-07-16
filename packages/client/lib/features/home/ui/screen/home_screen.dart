import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../bloc/home_tab_reselect_cubit.dart';
import '../bloc/new_stuff_cubit.dart';
import '../widget/friends_navbar_item.dart';
import '../widget/home_bottom_nav_listener.dart';
import '../widget/home_post_join_listener.dart';
import '../widget/inbox_navbar_item.dart';
import '../widget/inbox_needs_me_reporter.dart';
import '../widget/my_work_navbar_item.dart';
import '../widget/profile_navbar_item.dart';
import '../widget/updates_navbar_item.dart';

@RoutePage()
class HomeScreen extends StatelessWidget implements AutoRouteWrapper {
  const HomeScreen({super.key});

  static final _homeTabRoutes = [
    for (final spec in HomeTabSpec.all) spec.shell(),
  ];

  /// Keeps the home shell subtree (and its [AutoTabsRouter] state) alive when
  /// [wrappedRoute] reparents it after the account id arrives. Without this
  /// the tabs router is disposed and rebuilt from the bare tab roots —
  /// `TabsRouter.setupRoutes` has already consumed `pendingChildren`, so any
  /// pushed branch detail (e.g. a deep-linked beacon view) is silently
  /// dropped and the URL snaps back to the tab root.
  /// Covered by `test/app/router/home_tab_branch_routing_test.dart`.
  static final _shellSubtreeKey = GlobalKey(debugLabel: 'HomeShellSubtree');

  @override
  Widget wrappedRoute(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: GetIt.I<ScreenCubit>()),
      BlocProvider.value(value: GetIt.I<HomeTabReselectCubit>()),
      BlocProvider.value(value: GetIt.I<NewStuffCubit>()),
    ],
    child: BlocSelector<AuthCubit, AuthState, String>(
      bloc: GetIt.I<AuthCubit>(),
      selector: (state) => state.currentAccountId,
      builder: (_, accountId) => _InboxScope(
        accountId: accountId,
        child: KeyedSubtree(key: _shellSubtreeKey, child: this),
      ),
    ),
  );

  void _onDestinationSelected(
    BuildContext context,
    TabsRouter tabsRouter,
    int index,
  ) {
    final prev = tabsRouter.activeIndex;
    tabsRouter.setActiveIndex(index);
    if (index == prev) {
      // Reselecting the already-active tab jumps straight back to its root
      // page (e.g. the My Work list) instead of requiring repeated back-taps
      // out of a pushed detail. A detail can itself be the branch stack root
      // after a cold browser deep link, so `popUntilRoot` is insufficient.
      final tab = HomeTabSpec.fromIndex(index);
      if (tab == null) return;
      unawaited(resetHomeTabBranchToRoot(tabsRouter, tab.tab));
      context.read<HomeTabReselectCubit>().bump(tab.tab);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    // Shell chrome uses full viewport width; token density follows [WindowClass].
    return BlocSelector<ProfileCubit, ProfileState, String>(
      bloc: GetIt.I<ProfileCubit>(),
      selector: (state) => state.profile.displayName,
      builder: (context, profileTitle) {
        // Fixed tab label keeps the profile icon stable; long names go to tooltip.
        final profileTooltipLabel = profileTitle.isEmpty
            ? l10n.noName
            : profileTitle;
        final windowClass = context.windowClass;
        final useSideNav = windowClass != WindowClass.compact;
        return AutoTabsRouter(
          routes: _homeTabRoutes,
          // Instant tab switches: fade left the previous tab visible while URL
          // and rail selection already pointed at the new tab (desync).
          duration: Duration.zero,
          transitionBuilder: (context, child, animation) => child,
          builder: (context, child) {
            final tabsRouter = context.tabsRouter;
            final content = HomePostJoinListener(
              tabsRouter: tabsRouter,
              child: child,
            );
            return ListenableBuilder(
              // Rebuild on every navigation: branch-internal pushes don't
              // notify the TabsRouter, but chrome below derives from the
              // active branch's stack depth.
              listenable: context.router.root.navigationHistory,
              builder: (context, _) => _buildChrome(
                context,
                l10n: l10n,
                profileTooltipLabel: profileTooltipLabel,
                windowClass: windowClass,
                useSideNav: useSideNav,
                tabsRouter: tabsRouter,
                content: content,
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildChrome(
    BuildContext context, {
    required L10n l10n,
    required String profileTooltipLabel,
    required WindowClass windowClass,
    required bool useSideNav,
    required TabsRouter tabsRouter,
    required Widget content,
  }) {
    if (useSideNav) {
      final extendedRail = windowClass == WindowClass.expanded;
      return Scaffold(
        resizeToAvoidBottomInset: false,
        body: HomeBottomNavListener(
          tabsRouter: tabsRouter,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NavigationRail(
                extended: extendedRail,
                selectedIndex: tabsRouter.activeIndex,
                onDestinationSelected: (index) => _onDestinationSelected(
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
                  if (kUpdatesTabEnabled)
                    NavigationRailDestination(
                      icon: const UpdatesNavbarItem(),
                      selectedIcon: const UpdatesNavbarItem(selected: true),
                      label: Text(l10n.updatesTitle),
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
                    selectedIcon: Tooltip(
                      message: profileTooltipLabel,
                      child: const ProfileNavBarItem(
                        selected: true,
                      ),
                    ),
                    label: Text(l10n.profile),
                  ),
                ],
              ),
              const TenturaVerticalHairline(),
              Expanded(child: content),
            ],
          ),
        ),
      );
    }
    // Compact keeps details full-screen (frozen pre-Phase-2 behavior):
    // hide the bottom bar while the active branch shows a pushed detail.
    // The listener stays mounted on the body so tab-index sync survives.
    final activeBranch = tabsRouter.stackRouterOfIndex(tabsRouter.activeIndex);
    final branchShowsDetail = (activeBranch?.stackData.length ?? 1) > 1;
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: HomeBottomNavListener(
        tabsRouter: tabsRouter,
        child: content,
      ),
      bottomNavigationBar: branchShowsDetail
          ? null
          : NavigationBar(
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
                if (kUpdatesTabEnabled)
                  NavigationDestination(
                    icon: const UpdatesNavbarItem(),
                    selectedIcon: const UpdatesNavbarItem(selected: true),
                    label: l10n.updatesTitle,
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
                  selectedIcon: const ProfileNavBarItem(
                    selected: true,
                  ),
                  label: l10n.profile,
                  tooltip: profileTooltipLabel,
                ),
              ],
            ),
    );
  }
}

@visibleForTesting
Future<void> resetHomeTabBranchToRoot(TabsRouter tabsRouter, HomeTab tab) {
  final spec = HomeTabSpec.forTab(tab);
  final branch = tabsRouter.stackRouterOfIndex(spec.index);
  if (branch == null) return Future.value();

  // Replacing the stack also bypasses PopScope and normalizes a cold
  // deep-linked branch whose first (and only) page is a detail route.
  return branch.replaceAll([spec.rootRoute()]);
}

/// Provides the account-scoped [InboxCubit] and keeps the **last** account's
/// cubit alive while [accountId] is transiently empty (sign-out / account
/// switch). The kept-alive tab shell above still holds account-scoped screens
/// (Inbox); rebuilding them without `Provider<InboxCubit>` throws before the
/// router replaces the Home route. Prod web never sees that window — sign-out
/// unloads the page — but in-place sign-out (native, integration tests) does.
class _InboxScope extends StatefulWidget {
  const _InboxScope({
    required this.accountId,
    required this.child,
  });

  final String accountId;
  final Widget child;

  @override
  State<_InboxScope> createState() => _InboxScopeState();
}

class _InboxScopeState extends State<_InboxScope> {
  var _lastAccountId = '';

  @override
  Widget build(BuildContext context) {
    if (widget.accountId.isNotEmpty) {
      _lastAccountId = widget.accountId;
    }
    final id = _lastAccountId;
    if (id.isEmpty) return widget.child;
    return BlocProvider(
      key: ValueKey(id),
      create: (_) => InboxCubit(userId: id),
      child: InboxNeedsMeReporter(child: widget.child),
    );
  }
}
