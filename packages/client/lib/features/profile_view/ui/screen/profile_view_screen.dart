import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/friends/ui/widget/people_list_pane.dart';
import 'package:tentura/features/home/ui/widget/home_rail_frame.dart';

import '../bloc/profile_shared_beacons_cubit.dart';
import '../bloc/profile_view_cubit.dart';
import '../widget/blocked_profile_view_body.dart';
import '../widget/profile_shared_beacons_sliver.dart';
import '../widget/profile_view_app_bar.dart';
import '../widget/profile_view_body.dart';

@RoutePage()
class ProfileViewScreen extends StatelessWidget implements AutoRouteWrapper {
  const ProfileViewScreen({
    @PathParam('id') this.id = '',
    @QueryParam(kQueryProfileEntry) this.entry,
    super.key,
  });

  final String id;

  /// [kProfileEntryPeople] when opened from My people: a wide window then
  /// shows the people list beside the profile.
  final String? entry;

  @override
  Widget wrappedRoute(BuildContext context) => localScreenCubitScope(
    child: MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => ProfileViewCubit(id: id),
        ),
        BlocProvider(
          create: (_) => ProfileSharedBeaconsCubit(
            meId: GetIt.I<ProfileCubit>().state.profile.id,
            targetId: id,
          ),
        ),
      ],
      child: this,
    ),
  );

  @override
  Widget build(BuildContext context) => HomeRailFrame(
    selectedTab: HomeTab.network,
    // Material 3 list-detail: opened from My people, a wide window keeps
    // the people list beside the profile; the profile keeps its own URL.
    child: TenturaListDetailLayout(
      list: entry == kProfileEntryPeople
          ? TenturaListDetailSelection(
              selectedId: id,
              child: const PeopleListPane(),
            )
          : null,
      detail: TenturaSupportingPaneScope(
        builder: (context) => Scaffold(
          appBar: buildProfileViewAppBar(context),
          body: BlocBuilder<ProfileViewCubit, ProfileViewState>(
            buildWhen: (previous, current) =>
                previous.blockedProfile != current.blockedProfile,
            builder: (context, state) {
              if (state.isBlockedFallback) {
                return TenturaContentColumn(
                  child: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: context.tt.cardPadding,
                        sliver: BlockedProfileViewBody(
                          profile: state.blockedProfile!,
                        ),
                      ),
                    ],
                  ),
                );
              }
              // Material 3 supporting pane: who they are and what you can do
              // with them beside your shared network with them.
              return TenturaSupportingPaneLayout(
                onRefresh: () => Future.wait([
                  context.read<ProfileViewCubit>().fetch(),
                  context.read<ProfileSharedBeaconsCubit>().fetch(),
                ]),
                primarySlivers: [
                  SliverPadding(
                    padding: context.tt.cardPadding,
                    sliver: const ProfileViewBody(showNetwork: false),
                  ),
                ],
                supportingSlivers: const [
                  ProfileViewNetworkSliver(),
                  // Shared beacons (forwarded + co-help-offered)
                  ProfileSharedBeaconsSliver(),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}
