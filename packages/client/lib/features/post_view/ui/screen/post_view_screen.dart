import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_room_lease.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_room_surface.dart';

import '../bloc/post_view_cubit.dart';

class PostViewScreen extends StatefulWidget {
  const PostViewScreen({required this.id, super.key});

  final String id;

  @override
  State<PostViewScreen> createState() => _PostViewScreenState();
}

class _PostViewScreenState extends State<PostViewScreen> {
  late final BeaconRoomLease _roomLease = BeaconRoomLease(
    host: context.read<ThreadHostCubit>(),
  );

  @override
  void dispose() {
    _roomLease.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: TenturaTopBar.of(
      context,
      title: const SizedBox.shrink(),
      leading: BackButton(onPressed: () => Navigator.maybePop(context)),
    ),
    body: BeaconRoomSurface(
      host: context.read<PostViewCubit>(),
      roomLease: _roomLease,
    ),
  );
}
