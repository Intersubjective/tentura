import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/like/ui/bloc/like_cubit.dart';
import 'package:tentura/features/chat/ui/bloc/chat_news_cubit.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/friends/ui/bloc/friends_cubit.dart';
import 'package:tentura/features/favorites/ui/bloc/favorites_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
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

  @override
  Widget wrappedRoute(BuildContext context) => MultiBlocProvider(
    providers: [
      BlocProvider.value(value: GetIt.I<ScreenCubit>()),
      BlocProvider.value(value: GetIt.I<HomeTabReselectCubit>()),
      BlocProvider.value(value: GetIt.I<NewStuffCubit>()),
    ],
    child: MultiBlocListener(
      listeners: [
        const BlocListener<ScreenCubit, ScreenState>(
          listener: commonScreenBlocListener,
        ),
        BlocListener<AuthCubit, AuthState>(
          bloc: GetIt.I<AuthCubit>(),
          listener: commonScreenBlocListener,
        ),
        const BlocListener<ContextCubit, ContextState>(
          listener: commonScreenBlocListener,
        ),
        BlocListener<ChatNewsCubit, ChatNewsState>(
          bloc: GetIt.I<ChatNewsCubit>(),
          listener: commonScreenBlocListener,
        ),
        BlocListener<FavoritesCubit, FavoritesState>(
          bloc: GetIt.I<FavoritesCubit>(),
          listener: commonScreenBlocListener,
        ),
        BlocListener<FriendsCubit, FriendsState>(
          bloc: GetIt.I<FriendsCubit>(),
          listener: commonScreenBlocListener,
        ),
        BlocListener<LikeCubit, LikeState>(
          bloc: GetIt.I<LikeCubit>(),
          listener: commonScreenBlocListener,
        ),
        BlocListener<ProfileCubit, ProfileState>(
          bloc: GetIt.I<ProfileCubit>(),
          listener: commonScreenBlocListener,
        ),
        BlocListener<SettingsCubit, SettingsState>(
          bloc: GetIt.I<SettingsCubit>(),
          listener: commonScreenBlocListener,
        ),
      ],
      child: this,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return BlocSelector<ProfileCubit, ProfileState, String>(
      bloc: GetIt.I<ProfileCubit>(),
      selector: (state) => state.profile.title,
      builder: (context, profileTitle) {
        // Fixed tab label keeps the profile icon stable; long names go to tooltip.
        final profileTooltipLabel = profileTitle.isEmpty
            ? l10n.noName
            : profileTitle;
        return AutoTabsScaffold(
          bottomNavigationBuilder: (context, tabsRouter) {
            return HomeBottomNavListener(
              tabsRouter: tabsRouter,
              child: NavigationBar(
                onDestinationSelected: (index) {
                  final prev = tabsRouter.activeIndex;
                  tabsRouter.setActiveIndex(index);
                  if (index == prev) {
                    final reselect = context.read<HomeTabReselectCubit>();
                    if (index == 0) {
                      reselect.bumpInboxReselect();
                    } else if (index == 1) {
                      reselect.bumpMyWorkReselect();
                    }
                  }
                },
                selectedIndex: tabsRouter.activeIndex,
                destinations: [
                  NavigationDestination(
                    icon: const InboxNavbarItem(),
                    selectedIcon: const InboxNavbarItem(selected: true),
                    label: l10n.inbox,
                  ),
                  NavigationDestination(
                    icon: const MyWorkNavbarItem(),
                    selectedIcon: const MyWorkNavbarItem(selected: true),
                    label: l10n.myWork,
                  ),
                  NavigationDestination(
                    icon: const FriendsNavbarItem(),
                    selectedIcon: const FriendsNavbarItem(selected: true),
                    label: l10n.network,
                  ),
                  NavigationDestination(
                    icon: const ProfileNavBarItem(),
                    label: l10n.profile,
                    tooltip: profileTooltipLabel,
                  ),
                ],
              ),
            );
          },
          resizeToAvoidBottomInset: false,
          routes: const [
            InboxRoute(),
            MyWorkRoute(),
            FriendsRoute(),
            ProfileRoute(),
          ],
        );
      },
    );
  }
}
