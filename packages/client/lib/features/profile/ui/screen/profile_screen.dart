import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import 'package:tentura/features/opinion/ui/bloc/opinion_cubit.dart';
import 'package:tentura/features/opinion/ui/widget/opinion_list.dart';

import '../bloc/profile_cubit.dart';
import '../widget/profile_app_bar.dart';
import '../widget/profile_body.dart';

@RoutePage()
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      BlocSelector<ProfileCubit, ProfileState, Profile>(
        bloc: GetIt.I<ProfileCubit>(),
        selector: (state) => state.profile,
        builder: (_, profile) => BlocProvider(
          create: (_) => OpinionCubit(
            myProfile: profile,
            profileId: profile.id,
          ),
          child: Builder(
            builder: (context) => RefreshIndicator.adaptive(
              onRefresh: () => Future.wait([
                GetIt.I<ProfileCubit>().fetch(),
                context.read<OpinionCubit>().fetch(preserve: false),
              ]),
              child: CustomScrollView(
                slivers: [
                  // Header
                  ProfileAppBar(
                    key: Key('ProfileAppBar:${profile.id}'),
                    profile: profile,
                  ),

                  // Profile
                  SliverPadding(
                    padding: kPaddingAll,
                    sliver: ProfileBody(
                      key: Key('ProfileBody:${profile.id}'),
                      profile: profile,
                    ),
                  ),

                  // Opinions List
                  SliverPadding(
                    padding: kPaddingH,
                    sliver: OpinionList(
                      key: Key('OpinionList:${profile.id}'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
