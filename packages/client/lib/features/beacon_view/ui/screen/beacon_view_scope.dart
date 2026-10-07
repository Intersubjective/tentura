import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_open_clear_listener.dart';

/// Request collaborators shared by its route and a converted Post's pane.
class BeaconViewScope extends StatelessWidget {
  const BeaconViewScope({
    required this.id,
    required this.myProfile,
    required this.child,
    super.key,
  });

  final String id;
  final Profile myProfile;
  final Widget child;

  @override
  Widget build(BuildContext context) => BlocProvider(
    key: ValueKey('BeaconViewCubit:$id:${myProfile.id}'),
    create: (_) => BeaconViewCubit(myProfile: myProfile, id: id),
    child: MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) {
            final cubit = BeaconHierarchyCubit(beaconId: id);
            unawaited(cubit.loadParentReference());
            return cubit;
          },
        ),
        BlocProvider(
          create: (_) {
            final cubit = ThreadsCubit(beaconId: id);
            unawaited(cubit.fetch());
            return cubit;
          },
        ),
        BlocProvider(create: (_) => ThreadHostCubit(beaconId: id)),
      ],
      child: Builder(
        builder: (context) => BlocListener<BeaconViewCubit, BeaconViewState>(
          listenWhen: (p, c) =>
              c.beaconContentLoaded &&
              (p.beaconContentLoaded != c.beaconContentLoaded ||
                  p.beacon.status != c.beacon.status),
          listener: (context, state) {
            context.read<ThreadHostCubit>().syncBeaconStatus(
              state.beacon.status,
            );
          },
          child: BeaconOpenClearListener(beaconId: id, child: child),
        ),
      ),
    ),
  );
}
