import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/routes.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/utils/ui_consts.dart';
import 'package:tentura/ui/widget/avatar_image.dart';
import 'package:tentura/ui/widget/gradient_stack.dart';
import 'package:tentura/ui/widget/avatar_positioned.dart';
import 'package:tentura/ui/widget/share_code_icon_button.dart';

import 'package:tentura/features/beacon/ui/bloc/beacon_cubit.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_mine_list.dart';

import '../bloc/profile_cubit.dart';
import '../widget/profile_mine_menu_button.dart';

class ProfileMineScreen extends StatelessWidget {
  static GoRoute getRoute({GlobalKey<NavigatorState>? parentNavigatorKey}) =>
      GoRoute(
        path: pathHomeProfile,
        parentNavigatorKey: parentNavigatorKey,
        builder: (context, state) => const ProfileMineScreen(),
      );

  const ProfileMineScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final beaconCubit = context.read<BeaconCubit>();
    final profileCubit = context.read<ProfileCubit>();
    final userId = profileCubit.state.user.id;
    return RefreshIndicator.adaptive(
      onRefresh: () => Future.wait([
        profileCubit.fetch(),
        beaconCubit.fetch(),
      ]),
      child: CustomScrollView(
        slivers: [
          // Header
          SliverAppBar(
            actions: [
              // Graph View
              IconButton(
                icon: const Icon(Icons.hub_outlined),
                onPressed: () => context.push(Uri(
                  path: pathGraph,
                  queryParameters: {'focus': userId},
                ).toString()),
              ),

              // Share
              ShareCodeIconButton(
                header: userId,
                link: Uri.https(
                  appLinkBase,
                  pathProfileView,
                  {'id': userId},
                ),
              ),

              // More
              const ProfileMineMenuButton(),
            ],
            floating: true,
            expandedHeight: GradientStack.defaultHeight,
            flexibleSpace: FlexibleSpaceBar(
              background: GradientStack(
                children: [
                  AvatarPositioned(
                    child: BlocSelector<ProfileCubit, ProfileState, String>(
                      selector: (state) => state.user.imageId,
                      builder: (context, imageId) => AvatarImage(
                        size: AvatarPositioned.childSize,
                        userId: imageId,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Profile
          SliverToBoxAdapter(
            child: Padding(
              padding: paddingH20,
              child: BlocConsumer<ProfileCubit, ProfileState>(
                listenWhen: (p, c) => c.hasError,
                listener: (context, state) {
                  showSnackBar(
                    context,
                    isError: true,
                    text: state.error?.toString(),
                  );
                },
                builder: (context, state) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title
                    Text(
                      state.user.title.isEmpty ? 'No name' : state.user.title,
                      textAlign: TextAlign.left,
                      style: textTheme.headlineLarge,
                    ),
                    const Padding(padding: paddingV8),

                    // Description
                    Text(
                      state.user.description,
                      textAlign: TextAlign.left,
                      style: textTheme.bodyLarge,
                    ),
                    const Divider(),

                    // Create
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Beacons',
                          style: textTheme.titleLarge,
                        ),
                        FilledButton(
                          onPressed: () => context.push(pathBeaconCreate),
                          child: const Text('Create'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Beacons List
          const BeaconMineList(),
        ],
      ),
    );
  }
}
