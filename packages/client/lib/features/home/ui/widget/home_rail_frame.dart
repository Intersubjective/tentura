import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/home_attention_cubit.dart';
import 'home_rail_account_footer.dart';
import 'home_nav_destinations.dart';

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
    final meIndex = HomeTabSpec.forTab(HomeTab.me).index;
    void openTab(int index) {
      final spec = HomeTabSpec.fromIndex(index);
      if (spec == null) return;
      final root = context.router.root;
      root.innerRouterOf<TabsRouter>(HomeRoute.name)?.setActiveIndex(index);
      unawaited(root.replacePath(spec.path));
    }

    final rail = NavigationRail(
      extended: extended,
      selectedIndex: HomeTabSpec.destinationIndexFor(
        HomeTabSpec.forTab(selectedTab).index,
      ),
      onDestinationSelected: openTab,
      labelType: extended
          ? NavigationRailLabelType.none
          : NavigationRailLabelType.all,
      destinations: [
        for (final d in homeNavDestinations(l10n, badged: badged))
          NavigationRailDestination(
            icon: d.icon,
            selectedIcon: d.selectedIcon,
            label: Text(d.label),
          ),
      ],
      // The account at the rail's foot, as on Home.
      trailing: Expanded(
        child: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: EdgeInsets.only(bottom: context.tt.cardGap),
            child: HomeRailAccountFooter(
              extended: extended,
              selected: selectedTab == HomeTab.me,
              onPressed: () => openTab(meIndex),
            ),
          ),
        ),
      ),
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
