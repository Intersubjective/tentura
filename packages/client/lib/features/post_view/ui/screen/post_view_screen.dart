import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_room_lease.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_room_surface.dart';
import 'package:tentura/features/constellation/ui/util/constellation_focus_request.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/post_view_cubit.dart';
import '../widget/post_action.dart';
import '../widget/post_info_sheet.dart';

enum _MuteChoice {
  hour(Duration(hours: 1)),
  threeHours(Duration(hours: 3)),
  day(Duration(days: 1)),
  threeDays(Duration(days: 3)),
  forever(null);

  const _MuteChoice(this.duration);

  final Duration? duration;
}

/// A Post is its room. The app bar names it and counts who is in it; a tap on
/// it opens «О посте» with everything else. ↗ forwards, ⋮ keeps the
/// shortcuts (mute, pin, complain / leave / delete).
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
    final l10n = L10n.of(context)!;
    return BlocBuilder<PostViewCubit, PostViewState>(
      builder: (context, state) => Scaffold(
        appBar: TenturaTopBar.of(
          context,
          title: _Title(
            state: state,
            onTap: () => unawaited(_run(context, PostAction.info)),
          ),
          leading: BackButton(onPressed: () => Navigator.maybePop(context)),
          actions: [
            if (state.beacon.viewerCanForward)
              IconButton(
                icon: const Icon(Icons.north_east),
                tooltip: l10n.labelForward,
                onPressed: () => unawaited(_run(context, PostAction.forward)),
              ),
            _Overflow(
              state: state,
              onSelected: (action) => unawaited(_run(context, action)),
            ),
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

  Future<void> _run(BuildContext context, PostAction action) async {
    final cubit = context.read<PostViewCubit>();
    final screenCubit = context.read<ScreenCubit>();
    final room = context.read<ThreadHostCubit>().roomCubit;
    final id = cubit.beaconId;
    switch (action) {
      case PostAction.info:
        final picked = await showPostInfoSheet(
          context,
          cubit: cubit,
          host: context.read<ThreadHostCubit>(),
        );
        if (picked != null && context.mounted) await _run(context, picked);
      case PostAction.scrollToRoot:
        final rootId = cubit.state.beacon.postRootMessageId;
        if (rootId != null) room?.requestScrollToMessage(rootId);
      case PostAction.forward:
        await context.router.push(ForwardBeaconRoute(beaconId: id));
      case PostAction.mute:
        final choice = await _pickMuteChoice(context);
        if (choice != null) await cubit.mute(choice.duration);
      case PostAction.unmute:
        await cubit.unmute();
      case PostAction.pin:
        await cubit.pin();
      case PostAction.unpin:
        await cubit.unpin();
      case PostAction.forwardsGraph:
        screenCubit.showForwardsGraphFor(id);
      case PostAction.showOnField:
        ConstellationFocusRequest.instance.requested = id;
        screenCubit.showConstellation();
      case PostAction.allowForwarding:
        if (await _confirmAllowForwarding(context) && context.mounted) {
          await cubit.allowForwarding();
        }
      case PostAction.convertToRequest:
        final discoverable = await _confirmConvert(
          context,
          participants: room?.state.participants ?? const [],
          wasClosed:
              cubit.state.beacon.forwardPolicy ==
              BeaconForwardPolicyValue.closed,
        );
        if (discoverable != null && context.mounted) {
          await context.router.push(
            BeaconCreateRoute(
              convertFromPostId: id,
              convertIsDiscoverable: discoverable,
            ),
          );
        }
      case PostAction.complain:
        screenCubit.showComplaint(id);
      case PostAction.leave:
        if (await _confirmLeave(context) && context.mounted) {
          await cubit.leave();
        }
      case PostAction.delete:
        if (await _confirmDelete(context) && context.mounted) {
          await cubit.delete();
        }
    }
  }

  Future<_MuteChoice?> _pickMuteChoice(BuildContext context) {
    final l10n = L10n.of(context)!;
    return showDialog<_MuteChoice>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.postMenuMute),
        children: [
          for (final choice in _MuteChoice.values)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, choice),
              child: Text(switch (choice) {
                _MuteChoice.hour => l10n.postMuteHour,
                _MuteChoice.threeHours => l10n.postMuteThreeHours,
                _MuteChoice.day => l10n.postMuteDay,
                _MuteChoice.threeDays => l10n.postMuteThreeDays,
                _MuteChoice.forever => l10n.postMuteForever,
              }),
            ),
        ],
      ),
    );
  }

  Future<bool> _confirmLeave(BuildContext context) async {
    final l10n = L10n.of(context)!;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.postLeaveConfirmTitle),
            content: Text(l10n.postLeaveConfirmBody),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.buttonCancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(l10n.postLeaveConfirmAction),
              ),
            ],
          ),
        ) ??
        false;
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

  /// M7: the author's confirmation; resolves to the chosen discoverability,
  /// or null when cancelled.
  Future<bool?> _confirmConvert(
    BuildContext context, {
    required List<BeaconParticipant> participants,
    required bool wasClosed,
  }) {
    final l10n = L10n.of(context)!;
    final others = participants
        .where((p) => p.role != BeaconParticipantRoleBits.author)
        .length;
    var discoverable = true;
    return showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(l10n.postConvertTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${l10n.postConvertKeepsConversation(others)} '
                '${l10n.postConvertEveryoneCanHelp}',
              ),
              if (wasClosed) Text(l10n.postConvertForwardingOpens),
              Text(l10n.postConvertIrreversible),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: discoverable,
                onChanged: (v) => setState(() => discoverable = v ?? true),
                title: Text(l10n.postConvertDiscoverable),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.buttonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, discoverable),
              child: Text(l10n.postConvertNext),
            ),
          ],
        ),
      ),
    );
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

/// «‹Автор›: ‹начало поста›» over «N участников · 🔕»; the whole title opens
/// «О посте».
class _Title extends StatelessWidget {
  const _Title({required this.state, required this.onTap});

  final PostViewState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final author = state.beacon.author.shownName.isNotEmpty
        ? state.beacon.author.shownName
        : state.summary?.authorName ?? '';
    final excerpt = state.summary?.rootExcerpt.trim() ?? '';
    final muted = state.summary?.isMutedAt(DateTime.now()) ?? false;
    final title = excerpt.isEmpty
        ? author
        : l10n.postViewTitle(author, excerpt);
    return Semantics(
      button: true,
      hint: l10n.postHeaderOpenInfo,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TenturaText.titleSmall(tt.text),
            ),
            Row(
              children: [
                Flexible(
                  child: _MembersLine(
                    style: TenturaText.bodySmall(tt.textMuted),
                  ),
                ),
                if (muted) ...[
                  SizedBox(width: tt.tightGap),
                  Icon(
                    Icons.notifications_off_outlined,
                    size: tt.iconSize,
                    color: tt.textMuted,
                    semanticLabel: l10n.postConversationMuted,
                  ),
                ],
                if (state.summary?.isPinned ?? false) ...[
                  SizedBox(width: tt.tightGap),
                  Icon(
                    Icons.push_pin_outlined,
                    size: tt.iconSize,
                    color: tt.textMuted,
                    semanticLabel: l10n.postMenuUnpin,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// «N участников», counted from the room once it is loaded.
class _MembersLine extends StatelessWidget {
  const _MembersLine({required this.style});

  final TextStyle style;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ThreadHostCubit, ThreadHostState>(
        builder: (context, _) {
          final room = context.read<ThreadHostCubit>().roomCubit;
          if (room == null) return const SizedBox.shrink();
          return BlocBuilder<RoomCubit, RoomState>(
            bloc: room,
            buildWhen: (p, c) =>
                p.participants != c.participants ||
                p.participantsLoaded != c.participantsLoaded,
            builder: (context, roomState) {
              if (!roomState.participantsLoaded) {
                return const SizedBox.shrink();
              }
              final count = roomState.participants
                  .where((p) => p.roomAccess == RoomAccessBits.admitted)
                  .length;
              return Text(
                L10n.of(context)!.postHeaderMembers(count),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              );
            },
          );
        },
      );
}

/// ⋮: «О посте», mute and pin, then complain / leave / delete.
class _Overflow extends StatelessWidget {
  const _Overflow({required this.state, required this.onSelected});

  final PostViewState state;
  final ValueChanged<PostAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final now = DateTime.now();
    final summary = state.summary;
    final viewerId = context.read<PostViewCubit>().myProfile.id;
    final viewerIsAuthor = state.beacon.author.id == viewerId;
    final muted = summary?.isMutedAt(now) ?? false;

    PopupMenuItem<PostAction> item(
      PostAction value,
      IconData icon,
      String label, {
      bool destructive = false,
    }) => PopupMenuItem(
      value: value,
      child: _MenuRow(icon: icon, label: label, destructive: destructive),
    );

    return PopupMenuButton<PostAction>(
      icon: const Icon(Icons.more_vert),
      tooltip: MaterialLocalizations.of(context).showMenuTooltip,
      onSelected: onSelected,
      itemBuilder: (_) => [
        item(PostAction.info, Icons.info_outline, l10n.postMenuInfo),
        if (muted)
          item(
            PostAction.unmute,
            Icons.notifications_active_outlined,
            summary!.mutedForever
                ? l10n.postMenuUnmuteForever
                : l10n.postMenuUnmuteUntil(
                    postMuteUntilTime(summary.mutedUntil!, now),
                  ),
          )
        else
          item(
            PostAction.mute,
            Icons.notifications_off_outlined,
            '${l10n.postMenuMute} ›',
          ),
        if (summary?.isPinned ?? false)
          item(PostAction.unpin, Icons.push_pin, l10n.postMenuUnpin)
        else
          item(PostAction.pin, Icons.push_pin_outlined, l10n.postMenuPin),
        const PopupMenuDivider(),
        if (!viewerIsAuthor)
          item(PostAction.complain, Icons.flag_outlined, l10n.buttonComplaint),
        if (_viewerIsAddressee(context, viewerId))
          item(
            PostAction.leave,
            Icons.logout,
            l10n.postMenuLeave,
            destructive: true,
          ),
        if (viewerIsAuthor)
          item(
            PostAction.delete,
            Icons.delete_outline,
            l10n.postMenuDelete,
            destructive: true,
          ),
      ],
    );
  }

  /// Only a recipient can leave; the author mutes or deletes instead.
  bool _viewerIsAddressee(BuildContext context, String viewerId) {
    final participants =
        context.read<ThreadHostCubit>().roomCubit?.state.participants ??
        const [];
    return participants.any(
      (p) =>
          p.userId == viewerId && p.role == BeaconParticipantRoleBits.addressee,
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.icon,
    required this.label,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final fg = destructive ? scheme.error : scheme.onSurface;
    return Row(
      children: [
        Icon(
          icon,
          size: tt.iconSize,
          color: destructive ? fg : scheme.onSurfaceVariant,
        ),
        SizedBox(width: tt.avatarTextGap),
        Expanded(child: Text(label, style: TenturaText.bodyMedium(fg))),
      ],
    );
  }
}
