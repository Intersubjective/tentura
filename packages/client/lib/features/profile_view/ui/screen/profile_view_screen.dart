import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../bloc/profile_reviews_about_me_cubit.dart';
import '../bloc/profile_shared_beacons_cubit.dart';
import '../bloc/profile_view_cubit.dart';
import '../widget/blocked_profile_view_body.dart';
import '../widget/profile_shared_beacons_sliver.dart';
import '../widget/reviews_about_me_from_profile_sliver.dart';
import '../widget/profile_view_app_bar.dart';
import '../widget/profile_view_body.dart';

@RoutePage()
class ProfileViewScreen extends StatelessWidget implements AutoRouteWrapper {
  const ProfileViewScreen({
    @PathParam('id') this.id = '',
    super.key,
  });

  final String id;

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
        BlocProvider(
          create: (_) => ProfileReviewsAboutMeCubit(profileOwnerId: id),
        ),
      ],
      child: this,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
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
        return TenturaContentColumn(
          child: RefreshIndicator.adaptive(
            onRefresh: () => Future.wait([
              context.read<ProfileViewCubit>().fetch(),
              context.read<ProfileReviewsAboutMeCubit>().fetch(),
              context.read<ProfileSharedBeaconsCubit>().fetch(),
            ]),
            child: CustomScrollView(
              slivers: [
                // Body
                SliverPadding(
                  padding: context.tt.cardPadding,
                  sliver: ProfileViewBody(),
                ),

                ReviewsAboutMeFromProfileSliver(),

                // Shared beacons (forwarded + co-help-offered)
                ProfileSharedBeaconsSliver(),
              ],
            ),
          ),
        );
      },
    ),
  );
}
