import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';

import '../bloc/profile_cubit.dart';
import '../widget/profile_name_nudge.dart';
import '../widget/profile_app_bar.dart';
import '../widget/profile_body.dart';

@RoutePage()
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) => TenturaContentColumn(
    child: BlocSelector<ProfileCubit, ProfileState, Profile>(
      bloc: GetIt.I<ProfileCubit>(),
      selector: (state) => state.profile,
      builder: (_, profile) => RefreshIndicator.adaptive(
        onRefresh: GetIt.I<ProfileCubit>().fetch,
        child: CustomScrollView(
          slivers: [
            // Header
            ProfileAppBar(
              key: Key('ProfileAppBar:${profile.id}'),
              profile: profile,
            ),

            SliverPadding(
              padding: context.tt.cardPadding,
              sliver: SliverToBoxAdapter(
                child: ProfileNameNudge(profile: profile),
              ),
            ),

            // Profile
            SliverPadding(
              padding: context.tt.cardPadding,
              sliver: ProfileBody(
                key: Key('ProfileBody:${profile.id}'),
                profile: profile,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
