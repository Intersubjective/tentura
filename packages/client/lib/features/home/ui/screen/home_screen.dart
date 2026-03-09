import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/like/ui/bloc/like_cubit.dart';
import 'package:tentura/features/chat/ui/bloc/chat_news_cubit.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/friends/ui/bloc/friends_cubit.dart';
import 'package:tentura/features/favorites/ui/bloc/favorites_cubit.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../widget/friends_navbar_item.dart';
import '../widget/profile_navbar_item.dart';

@RoutePage()
class HomeScreen extends StatelessWidget implements AutoRouteWrapper {
  const HomeScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) => BlocProvider.value(
    value: GetIt.I<ScreenCubit>(),
    child: MultiBlocListener(
      listeners: [
        const BlocListener<ScreenCubit, ScreenState>(
          listener: commonScreenBlocListener,
        ),
        // Auth
        BlocListener<AuthCubit, AuthState>(
          bloc: GetIt.I<AuthCubit>(),
          listener: commonScreenBlocListener,
        ),
        // Context
        const BlocListener<ContextCubit, ContextState>(
          listener: commonScreenBlocListener,
        ),
        // ChatNews
        BlocListener<ChatNewsCubit, ChatNewsState>(
          bloc: GetIt.I<ChatNewsCubit>(),
          listener: commonScreenBlocListener,
        ),
        // Favorites
        BlocListener<FavoritesCubit, FavoritesState>(
          bloc: GetIt.I<FavoritesCubit>(),
          listener: commonScreenBlocListener,
        ),
        // Friends
        BlocListener<FriendsCubit, FriendsState>(
          bloc: GetIt.I<FriendsCubit>(),
          listener: commonScreenBlocListener,
        ),
        // Like
        BlocListener<LikeCubit, LikeState>(
          bloc: GetIt.I<LikeCubit>(),
          listener: commonScreenBlocListener,
        ),
        // Profile
        BlocListener<ProfileCubit, ProfileState>(
          bloc: GetIt.I<ProfileCubit>(),
          listener: commonScreenBlocListener,
        ),
        // Settings
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
    return AutoTabsScaffold(
      bottomNavigationBuilder: (context, tabsRouter) {
        final l10n = L10n.of(context)!;
        return NavigationBar(
          onDestinationSelected: tabsRouter.setActiveIndex,
          indicatorColor: Theme.of(context).colorScheme.primaryFixed,
          selectedIndex: tabsRouter.activeIndex,
          destinations: [
            NavigationDestination(
              icon: const Icon(TenturaIcons.home),
              label: l10n.myField,
            ),
            NavigationDestination(
              icon: const Icon(Icons.star_border),
              label: l10n.favorites,
            ),
            NavigationDestination(
              icon: const Icon(TenturaIcons.affiliation),
              label: l10n.connect,
            ),
            NavigationDestination(
              icon: const FriendsNavbarItem(),
              label: l10n.friends,
            ),
            NavigationDestination(
              icon: const ProfileNavBarItem(),
              label: l10n.profile,
            ),
          ],
        );
      },
      resizeToAvoidBottomInset: false,
      routes: const [
        MyFieldRoute(),
        FavoritesRoute(),
        ConnectRoute(),
        FriendsRoute(),
        ProfileRoute(),
      ],
    );
  }
}
