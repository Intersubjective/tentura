import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_room_lease.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_room_surface.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/post_view_cubit.dart';
import '../widget/post_participants_sheet.dart';

enum _PostAction {
  participants,
  forwardsGraph,
  showOnField,
  forward,
  allowForwarding,
  delete,
}

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
  Widget build(BuildContext context) {
    final cubit = context.read<PostViewCubit>();
    return BlocBuilder<PostViewCubit, PostViewState>(
      builder: (context, state) => Scaffold(
        appBar: TenturaTopBar.of(
          context,
          title: _Title(state: state),
          leading: BackButton(onPressed: () => Navigator.maybePop(context)),
          actions: [
            if (state.summary?.isMutedAt(DateTime.now()) ?? false)
              Icon(
                Icons.notifications_off_outlined,
                semanticLabel: L10n.of(context)!.postConversationMuted,
              ),
            _Overflow(state: state),
          ],
        ),
        body: BeaconRoomSurface(
          host: cubit,
          roomLease: _roomLease,
          postRoot: _postRoot(state),
        ),
      ),
    );
  }

  RoomPostRootPin? _postRoot(PostViewState state) {
    final rootId = state.beacon.postRootMessageId;
    if (rootId == null) return null;
    final edge = state.forwardedToMe;
    return RoomPostRootPin(
      messageId: rootId,
      excerpt: state.summary?.rootExcerpt.trim() ?? '',
      forwardedBy: edge?.sender.shownName ?? '',
      forwardNote: edge?.note.trim() ?? '',
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.state});

  final PostViewState state;

  @override
  Widget build(BuildContext context) {
    final author = state.beacon.author.shownName.isNotEmpty
        ? state.beacon.author.shownName
        : state.summary?.authorName ?? '';
    final excerpt = state.summary?.rootExcerpt.trim() ?? '';
    return Text(
      excerpt.isEmpty
          ? author
          : L10n.of(context)!.postViewTitle(author, excerpt),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _Overflow extends StatelessWidget {
  const _Overflow({required this.state});

  final PostViewState state;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final beacon = state.beacon;
    final viewerIsAuthor =
        beacon.author.id == context.read<PostViewCubit>().myProfile.id;
    return PopupMenuButton<_PostAction>(
      icon: const Icon(Icons.more_vert),
      onSelected: (action) => unawaited(_run(context, action)),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: _PostAction.participants,
          child: Text(l10n.postMenuParticipants),
        ),
        PopupMenuItem(
          value: _PostAction.forwardsGraph,
          child: Text(l10n.forwardsGraphMenuTitle),
        ),
        PopupMenuItem(
          value: _PostAction.showOnField,
          child: Text(l10n.postMenuShowOnField),
        ),
        if (beacon.viewerCanForward)
          PopupMenuItem(
            value: _PostAction.forward,
            child: Text(l10n.labelForward),
          ),
        if (viewerIsAuthor &&
            beacon.forwardPolicy == BeaconForwardPolicyValue.closed)
          PopupMenuItem(
            value: _PostAction.allowForwarding,
            child: Text(l10n.postMenuAllowForwarding),
          ),
        if (viewerIsAuthor)
          PopupMenuItem(
            value: _PostAction.delete,
            child: Text(l10n.postMenuDelete),
          ),
      ],
    );
  }

  Future<void> _run(BuildContext context, _PostAction action) async {
    final cubit = context.read<PostViewCubit>();
    final screenCubit = context.read<ScreenCubit>();
    final id = cubit.beaconId;
    switch (action) {
      case _PostAction.participants:
        final room = context.read<ThreadHostCubit>().roomCubit;
        await showPostParticipantsSheet(
          context,
          participants: room?.state.participants ?? const [],
        );
      case _PostAction.forwardsGraph:
        screenCubit.showForwardsGraphFor(id);
      case _PostAction.showOnField:
        screenCubit.showConstellation();
      case _PostAction.forward:
        await context.router.push(ForwardBeaconRoute(beaconId: id));
      case _PostAction.allowForwarding:
        if (await _confirmAllowForwarding(context) && context.mounted) {
          await cubit.allowForwarding();
        }
      case _PostAction.delete:
        if (await _confirmDelete(context) && context.mounted) {
          await cubit.delete();
        }
    }
  }

  Future<bool> _confirmAllowForwarding(BuildContext context) async {
    final l10n = L10n.of(context)!;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.postAllowForwardingTitle),
            content: Text(l10n.postAllowForwardingBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.buttonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.postAllowForwardingAction),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final l10n = L10n.of(context)!;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.postDeleteConfirmTitle),
            content: Text(l10n.postDeleteConfirmBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.buttonCancel),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(ctx).colorScheme.error,
                ),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.beaconRoomDeleteMessageConfirmAction),
              ),
            ],
          ),
        ) ??
        false;
  }
}
