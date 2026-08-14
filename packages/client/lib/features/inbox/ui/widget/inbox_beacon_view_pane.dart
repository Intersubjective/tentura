import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Inbox expanded detail pane: full BeaconView without a nested Scaffold/route.
class InboxBeaconViewPane extends StatelessWidget {
  const InboxBeaconViewPane({
    required this.beaconId,
    super.key,
  });

  final String beaconId;

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
                  'InboxBeaconView:$beaconId:${myProfile.id}',
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
              entry: kBeaconEntryInbox,
              embedded: true,
            ),
          );
        },
      ),
    );
  }
}
