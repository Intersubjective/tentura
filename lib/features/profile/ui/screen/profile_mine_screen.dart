import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_image.dart';
import 'package:tentura/ui/widget/gradient_stack.dart';
import 'package:tentura/ui/widget/avatar_positioned.dart';
import 'package:tentura/ui/widget/share_code_icon_button.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/beacon/ui/bloc/beacon_cubit.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_info.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_mine_control.dart';

import '../bloc/profile_cubit.dart';
import '../widget/profile_mine_menu_button.dart';

@RoutePage()
class ProfileMineScreen extends StatelessWidget implements AutoRouteWrapper {
  const ProfileMineScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) =>
      BlocSelector<AuthCubit, AuthState, String>(
          bloc: GetIt.I<AuthCubit>(),
          selector: (state) => state.currentAccountId,
          builder: (context, accountId) => MultiBlocProvider(
                key: Key('ProfileMineScreenProvider:$accountId'),
                providers: [
                  BlocProvider.value(value: GetIt.I<ProfileCubit>()),
                  BlocProvider(create: (_) => BeaconCubit(userId: accountId)),
                ],
                child: this,
              ));

  @override
  Widget build(BuildContext context) => MultiBlocListener(
        listeners: [
          BlocListener<BeaconCubit, BeaconState>(
            listenWhen: (p, c) => c.hasError,
            listener: showSnackBarError,
          ),
          BlocListener<ProfileCubit, ProfileState>(
            listenWhen: (p, c) => c.hasError,
            listener: showSnackBarError,
          ),
        ],
        child: RefreshIndicator.adaptive(
          onRefresh: () async => Future.wait([
            context.read<BeaconCubit>().fetch(),
            context.read<ProfileCubit>().fetch(),
          ]),
          child: Builder(
            builder: (context) {
              final textTheme = Theme.of(context).textTheme;
              final beaconsCubit = context.watch<BeaconCubit>();
              final profileCubit = context.watch<ProfileCubit>();
              final beacons = beaconsCubit.state.beacons;
              final profile = profileCubit.state.profile;
              return CustomScrollView(
                slivers: [
                  // Header
                  SliverAppBar(
                    // key: ValueKey(user.imageId),
                    key: Key('ProfileMineScreen:${profile.imageId}'),
                    actions: [
                      // Graph View
                      IconButton(
                        icon: const Icon(Icons.hub_outlined),
                        onPressed: () async =>
                            context.pushRoute(GraphRoute(focus: profile.id)),
                      ),

                      // Share
                      ShareCodeIconButton.id(profile.id),

                      // More
                      const ProfileMineMenuButton(),
                    ],
                    floating: true,
                    expandedHeight: GradientStack.defaultHeight,
                    flexibleSpace: FlexibleSpaceBar(
                      background: GradientStack(
                        children: [
                          AvatarPositioned(
                            child: AvatarImage(
                              userId: profile.imageId,
                              size: AvatarPositioned.childSize,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Profile
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: paddingMediumH,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Title
                          Text(
                            profile.title.isEmpty ? 'No name' : profile.title,
                            textAlign: TextAlign.left,
                            style: textTheme.headlineLarge,
                          ),
                          const Padding(padding: paddingSmallV),

                          // Description
                          Text(
                            profile.description,
                            textAlign: TextAlign.left,
                            style: textTheme.bodyLarge,
                          ),
                          const Divider(),

                          // Create
                          Row(
                            // key: const Key('Control_Row'),
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Beacons',
                                style: textTheme.titleLarge,
                              ),
                              FilledButton(
                                onPressed: () async => context
                                    .pushRoute(const BeaconCreateRoute()),
                                child: const Text('Create'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Beacons List
                  SliverList.separated(
                    itemCount: beacons.length,
                    itemBuilder: (context, i) => Padding(
                      padding: paddingMediumH,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BeaconInfo(beacon: beacons[i]),
                          Padding(
                            padding: paddingSmallV,
                            child: BeaconMineControl(beacon: beacons[i]),
                          ),
                        ],
                      ),
                    ),
                    separatorBuilder: (_, __) => const Divider(
                      endIndent: 20,
                      indent: 20,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
}
