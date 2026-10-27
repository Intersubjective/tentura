import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/utils/post_expiry_clock.dart';

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
    child: MultiBlocProvider(
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
      child: _RoomLifecycleSync(
        child: PostViewScreen(id: id, inPane: onClose != null),
      ),
    ),
  );
}

/// Keeps the room's lifecycle in step with the Post: its status and whether
/// it is past `expiresAt`. A remote change of either (a shorten leaves the
/// status open) and the clock passing `expiresAt` both reach the room.
class _RoomLifecycleSync extends StatefulWidget {
  const _RoomLifecycleSync({required this.child});

  final Widget child;

  @override
  State<_RoomLifecycleSync> createState() => _RoomLifecycleSyncState();
}

class _RoomLifecycleSyncState extends State<_RoomLifecycleSync> {
  late final PostViewCubit _cubit = context.read<PostViewCubit>();

  late final PostExpiryClock _expiryClock = PostExpiryClock(
    onTick: () => _sync(_cubit.state),
    clock: _cubit.now,
  );

  @override
  void initState() {
    super.initState();
    if (_cubit.state.status is StateIsSuccess) _sync(_cubit.state);
  }

  @override
  void dispose() {
    _expiryClock.dispose();
    super.dispose();
  }

  void _sync(PostViewState state) {
    if (!mounted || state.status is! StateIsSuccess) return;
    final beacon = state.beacon;
    _expiryClock.setDeadlines({?beacon.expiresAt});
    context.read<ThreadHostCubit>().syncBeaconStatus(
      beacon.status,
      authorId: beacon.author.id,
      expired: beacon.isPostArchivedAt(_cubit.now()),
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<PostViewCubit, PostViewState>(
        listenWhen: (p, c) =>
            c.status is StateIsSuccess &&
            (p.status is! StateIsSuccess ||
                p.beacon.status != c.beacon.status ||
                p.beacon.expiresAt != c.beacon.expiresAt),
        listener: (context, state) => _sync(state),
        child: widget.child,
      );
}
