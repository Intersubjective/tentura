import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/home_attention_cubit.dart';
import 'constellation_navbar_item.dart';
import 'friends_navbar_item.dart';
import 'inbox_navbar_item.dart';
import 'my_work_navbar_item.dart';
import 'profile_navbar_item.dart';

/// Home's side navigation around a root route that covers the Home page.
///
/// Root browse routes (Request detail, Following, Rejected, Updates, other
/// people's profiles, Edit profile) are pushed above Home, so on a regular or
/// expanded window they used to drop the rail and the person lost where they
/// were. This frame puts the same rail — same destinations, badges and
/// avatar as Home's — back beside them. Compact windows keep full-screen
/// details and get [child] unchanged.
///
/// Wrap the whole [Scaffold] so its app bar and body share the post-rail
/// width (split header panes line up with the body, #169).
class HomeRailFrame extends StatelessWidget {
  const HomeRailFrame({
    required this.selectedTab,
    required this.child,
    super.key,
  });

  /// The Home tab this route belongs to.
  final HomeTab selectedTab;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.windowClass == WindowClass.compact) return child;

    final l10n = L10n.of(context)!;
    final extended = context.windowClass == WindowClass.expanded;
    // Badged items read Home's attention cubit; a route rendered without it
    // (isolated widget tests) falls back to plain glyphs.
    final badged = GetIt.I.isRegistered<HomeAttentionCubit>();
    final rail = NavigationRail(
      extended: extended,
      selectedIndex: HomeTabSpec.forTab(selectedTab).index,
      onDestinationSelected: (index) {
        final spec = HomeTabSpec.fromIndex(index);
        if (spec == null) return;
        final root = context.router.root;
        root.innerRouterOf<TabsRouter>(HomeRoute.name)?.setActiveIndex(index);
        unawaited(root.replacePath(spec.path));
      },
      labelType: extended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      destinations: [
        NavigationRailDestination(
          icon: badged
              ? const MyWorkNavbarItem()
              : const Icon(Icons.work_outline),
          selectedIcon: badged
              ? const MyWorkNavbarItem(selected: true)
              : const Icon(Icons.work),
          label: Text(l10n.myWork),
        ),
        NavigationRailDestination(
          icon: badged
              ? const InboxNavbarItem()
              : const Icon(Icons.inbox_outlined),
          selectedIcon: badged
              ? const InboxNavbarItem(selected: true)
              : const Icon(Icons.inbox),
          label: Text(l10n.inbox),
        ),
        NavigationRailDestination(
          icon: badged
              ? const ConstellationNavbarItem()
              : const Icon(TenturaIcons.graph),
          selectedIcon: badged
              ? const ConstellationNavbarItem(selected: true)
              : const Icon(TenturaIcons.graph),
          label: Text(l10n.constellationNavLabel),
        ),
        NavigationRailDestination(
          icon: badged
              ? const FriendsNavbarItem()
              : const Icon(Icons.people_outline),
          selectedIcon: badged
              ? const FriendsNavbarItem(selected: true)
              : const Icon(Icons.people),
          label: Text(l10n.network),
        ),
        NavigationRailDestination(
          icon: badged
              ? const ProfileNavBarItem()
              : const Icon(Icons.person_outline),
          selectedIcon: badged
              ? const ProfileNavBarItem(selected: true)
              : const Icon(Icons.person),
          label: Text(l10n.profile),
        ),
      ],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (badged)
          BlocProvider.value(value: GetIt.I<HomeAttentionCubit>(), child: rail)
        else
          rail,
        const TenturaVerticalHairline(),
        Expanded(child: child),
      ],
    );
  }
}
