import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
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
    this.embeddedRoomCoVisible = false,
    this.suppressEmbeddedRoomBack = false,
    this.embeddedRoomCloseNonce = 0,
    this.onEmbeddedRoomOpenChanged,
    this.onEmbeddedLeave,
    super.key,
  });

  final String beaconId;
  final String? viewTab;
  final String? peopleTabAttention;
  final bool embeddedRoomCoVisible;
  final bool suppressEmbeddedRoomBack;
  final int embeddedRoomCloseNonce;
  final ValueChanged<bool>? onEmbeddedRoomOpenChanged;
  final VoidCallback? onEmbeddedLeave;

  @override
  Widget build(BuildContext context) {
    return localScreenCubitScope(
      child: BlocBuilder<ProfileCubit, ProfileState>(
        buildWhen: (previous, current) =>
            previous.profile.id != current.profile.id,
        builder: (context, profileState) {
          final myProfile = profileState.profile;
          return BlocProvider(
            key: ValueKey(
              'MyWorkBeaconView:$beaconId:${myProfile.id}:$viewTab:$peopleTabAttention',
            ),
            create: (_) => BeaconViewCubit(
              myProfile: myProfile,
              id: beaconId,
            ),
            child: BeaconViewScreen(
              id: beaconId,
              entry: kBeaconEntryMyWork,
              viewTab: viewTab,
              peopleTabAttention: peopleTabAttention,
              embedded: true,
              embeddedAllowRoomSplit: true,
              embeddedRoomCoVisible: embeddedRoomCoVisible,
              suppressEmbeddedRoomBack: suppressEmbeddedRoomBack,
              embeddedRoomCloseNonce: embeddedRoomCloseNonce,
              onEmbeddedRoomOpenChanged: onEmbeddedRoomOpenChanged,
              onEmbeddedLeave: onEmbeddedLeave,
            ),
          );
        },
      ),
    );
  }
}
