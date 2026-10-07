import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_scope.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../bloc/post_view_cubit.dart';
import 'post_view_screen.dart';

/// A Post's cubits around its [PostViewScreen].
///
/// Built by the Post's own route and by Inbox's list-detail pane, which
/// passes [onClose] so delete / leave clear its selection instead of popping
/// Home.
class PostViewScope extends StatelessWidget {
  const PostViewScope({
    required this.id,
    required this.myProfile,
    this.onClose,
    super.key,
  });

  final String id;

  final Profile myProfile;

  /// Non-null in a list-detail pane: the screen drops its back button.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) => BlocProvider(
    key: ValueKey('PostViewCubit:$id:${myProfile.id}'),
    create: (_) {
      final cubit = PostViewCubit(
        id: id,
        myProfile: myProfile,
        onClose: onClose,
      );
      unawaited(cubit.fetch());
      return cubit;
    },
    child: BlocBuilder<PostViewCubit, PostViewState>(
      buildWhen: (previous, current) =>
          previous.beacon.kind != current.beacon.kind,
      builder: (context, state) {
        if (state.beacon.kind == BeaconKind.request) {
          return BeaconViewScope(
            id: id,
            myProfile: myProfile,
            child: BeaconViewScreen(id: id, syncRoute: onClose == null),
          );
        }
        return MultiBlocProvider(
          providers: [
            BlocProvider(
              create: (_) {
                final cubit = ThreadsCubit(beaconId: id);
                unawaited(cubit.fetch());
                return cubit;
              },
            ),
            BlocProvider(
              create: (_) => ThreadHostCubit(
                beaconId: id,
                capabilities: const RoomCapabilities.post(),
              ),
            ),
          ],
          child: Builder(
            builder: (context) => BlocListener<PostViewCubit, PostViewState>(
              listenWhen: (p, c) =>
                  c.status is StateIsSuccess &&
                  (p.status is! StateIsSuccess ||
                      p.beacon.status != c.beacon.status),
              listener: (context, state) {
                context.read<ThreadHostCubit>().syncBeaconStatus(
                  state.beacon.status,
                );
              },
              child: PostViewScreen(id: id, inPane: onClose != null),
            ),
          ),
        );
      },
    ),
  );
}
