import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/like/ui/bloc/like_cubit.dart';
import 'package:tentura/features/beacon/ui/bloc/beacon_cubit.dart';
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
  Widget wrappedRoute(BuildContext context) => MultiBlocListener(
        listeners: [
          // Auth
          BlocListener<AuthCubit, AuthState>(
            bloc: GetIt.I<AuthCubit>(),
            listener: commonScreenBlocListener,
          ),
          // Beacon
          BlocListener<BeaconCubit, BeaconState>(
            bloc: GetIt.I<BeaconCubit>(),
            listener: commonScreenBlocListener,
          ),
          // Context
          BlocListener<ContextCubit, ContextState>(
            bloc: GetIt.I<ContextCubit>(),
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
      );

  @override
  Widget build(BuildContext context) => AutoTabsScaffold(
        bottomNavigationBuilder: (context, tabsRouter) => NavigationBar(
          onDestinationSelected: tabsRouter.setActiveIndex,
          selectedIndex: tabsRouter.activeIndex,
          destinations: const [
            NavigationDestination(
              icon: Icon(TenturaIcons.home),
              label: 'My field',
            ),
            NavigationDestination(
              icon: Icon(Icons.star_border),
              label: 'Favorites',
            ),
            NavigationDestination(
              icon: Icon(TenturaIcons.affiliation),
              label: 'Connect',
            ),
            NavigationDestination(
              icon: FriendsNavbarItem(),
              label: 'Friends',
            ),
            NavigationDestination(
              icon: ProfileNavBarItem(),
              label: 'Profile',
            ),
          ],
        ),
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
