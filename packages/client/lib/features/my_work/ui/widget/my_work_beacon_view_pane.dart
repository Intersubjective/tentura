import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// My Work expanded detail pane: full BeaconView without a nested Scaffold/route.
class MyWorkBeaconViewPane extends StatelessWidget {
  const MyWorkBeaconViewPane({
    required this.beaconId,
    this.viewTab,
    this.peopleTabAttention,
    this.onRequestThreadRoute,
    this.onEmbeddedLeave,
    super.key,
  });

  final String beaconId;
  final String? viewTab;
  final String? peopleTabAttention;
  final void Function(String threadId, String? messageId)? onRequestThreadRoute;
  final VoidCallback? onEmbeddedLeave;

  @override
  Widget build(BuildContext context) {
    return localScreenCubitScope(
      child: BlocBuilder<ProfileCubit, ProfileState>(
        buildWhen: (previous, current) =>
            previous.profile.id != current.profile.id,
        builder: (context, profileState) {
          final myProfile = profileState.profile;
          return MultiBlocProvider(
            providers: [
              BlocProvider(
                key: ValueKey(
                  'MyWorkBeaconView:$beaconId:${myProfile.id}:$viewTab:$peopleTabAttention',
                ),
                create: (_) => BeaconViewCubit(
                  myProfile: myProfile,
                  id: beaconId,
                ),
              ),
              BlocProvider(
                create: (_) => ThreadsCubit(beaconId: beaconId)..fetch(),
              ),
              BlocProvider(
                create: (_) => ThreadHostCubit(beaconId: beaconId),
              ),
            ],
            child: BeaconViewScreen(
              id: beaconId,
              entry: kBeaconEntryMyWork,
              viewTab: viewTab,
              peopleTabAttention: peopleTabAttention,
              embedded: true,
              onRequestThreadRoute: onRequestThreadRoute,
              onEmbeddedLeave: onEmbeddedLeave,
            ),
          );
        },
      ),
    );
  }
}
