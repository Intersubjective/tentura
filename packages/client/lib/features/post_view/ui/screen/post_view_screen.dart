import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/post_people.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_state.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_room_lease.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_room_surface.dart';
import 'package:tentura/features/constellation/ui/util/constellation_focus_request.dart';
import 'package:tentura/features/forward/ui/widget/beacon_invite_flow.dart';
import 'package:tentura/features/invitation/ui/bloc/invitation_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/post_expiry_clock.dart';

import '../bloc/post_view_cubit.dart';
import '../post_remaining_label.dart';
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

/// The ends «Сократить срок» offers; each is only offered when strictly
/// earlier than the current end. `closeNow` is always offered.
enum _ShortenChoice {
  hour(Duration(hours: 1)),
  sixHours(Duration(hours: 6)),
  day(Duration(hours: 24)),
  closeNow(null);

  const _ShortenChoice(this.duration);

  final Duration? duration;
}

/// A Post is its room. The app bar names it and counts who is in it; a tap on
/// it opens «О посте» with everything else. ↗ forwards, ⋮ keeps the
/// shortcuts (mute, pin, complain / leave / delete).
class PostViewScreen extends StatefulWidget {
  const PostViewScreen({
    required this.id,
    this.inPane = false,
    this.postBuddingEnabled = kPostBuddingEnabled,
    super.key,
  });

  final String id;

  /// Offers «Оформить запрос» in ⋮; defaults to [kPostBuddingEnabled].
  final bool postBuddingEnabled;

  /// Shown beside Inbox's conversation list: nothing to go back to.
  final bool inPane;

  @override
  State<PostViewScreen> createState() => _PostViewScreenState();
}

class _PostViewScreenState extends State<PostViewScreen> {
  late final BeaconRoomLease _roomLease = BeaconRoomLease(
    host: context.read<ThreadHostCubit>(),
  );

  // Re-evaluates the countdown and the author's lifetime actions at the
  // deadline and during the last hour, with no network event.
  late final PostExpiryClock _expiryClock = PostExpiryClock(
    onTick: () {
      if (mounted) setState(() {});
    },
    clock: context.read<PostViewCubit>().now,
  );

  @override
  void initState() {
    super.initState();
    _watchDeadline(context.read<PostViewCubit>().state);
  }

  void _watchDeadline(PostViewState state) {
    final expiresAt = state.beacon.expiresAt;
    _expiryClock.setDeadlines({?expiresAt});
  }

  @override
  void dispose() {
    _expiryClock.dispose();
    _roomLease.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PostViewCubit>();
    final l10n = L10n.of(context)!;
    return BlocConsumer<PostViewCubit, PostViewState>(
      listenWhen: (p, c) => p.beacon.expiresAt != c.beacon.expiresAt,
      listener: (_, state) => _watchDeadline(state),
      builder: (context, state) => Scaffold(
        appBar: TenturaTopBar.of(
          context,
          title: _Title(
            state: state,
            now: cubit.now(),
            onTap: () => unawaited(_run(context, PostAction.info)),
          ),
          leading: widget.inPane
              ? null
              : BackButton(onPressed: () => Navigator.maybePop(context)),
          actions: [
            if (state.beacon.viewerCanForward && !_isClosed(state))
              IconButton(
                icon: const Icon(Icons.north_east),
                tooltip: l10n.labelForward,
                onPressed: () => unawaited(_run(context, PostAction.forward)),
              ),
            _Overflow(
              state: state,
              lifetimeNow: cubit.now(),
              postBuddingEnabled: widget.postBuddingEnabled,
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
    // #667: the author sending their own Post started the chat; only someone
    // else passing it on is a forward.
    final senderName = edge?.sender.shownName ?? '';
    final fromAuthor = edge?.sender.id == state.beacon.author.id;
    return RoomPostRootPin(
      messageId: rootId,
      excerpt: state.summary?.rootExcerpt.trim() ?? '',
      forwardedBy: fromAuthor ? '' : senderName,
      // The author's personal note stays next to the started line.
      forwardNote: edge?.note.trim() ?? '',
      startedBy: fromAuthor ? senderName : '',
    );
  }

  Future<void> _run(BuildContext context, PostAction action) async {
    final cubit = context.read<PostViewCubit>();
    final screenCubit = context.read<ScreenCubit>();
    final room = context.read<ThreadHostCubit>().roomCubit;
    final id = cubit.beaconId;
    switch (action) {
      case PostAction.info:
      case PostAction.participants:
        final picked = await showPostInfoSheet(
          context,
          cubit: cubit,
          host: context.read<ThreadHostCubit>(),
          scrollToParticipants: action == PostAction.participants,
        );
        if (picked != null && context.mounted) await _run(context, picked);
      case PostAction.scrollToRoot:
        final rootId = cubit.state.beacon.postRootMessageId;
        if (rootId != null) room?.requestScrollToMessage(rootId);
      case PostAction.forward:
        await context.router.push(ForwardBeaconRoute(beaconId: id));
      case PostAction.invite:
        // Straight to the invite dialog, not the Forward screen (#715).
        final invitations = InvitationCubit();
        try {
          await runBeaconInviteFlow(
            context,
            invitations: invitations,
            beaconId: id,
            isPost: true,
          );
        } finally {
          await invitations.close();
        }
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
        screenCubit.showForwardsGraphFor(id, kind: BeaconKind.post);
      case PostAction.showOnField:
        ConstellationFocusRequest.instance.requested = id;
        screenCubit.showConstellation();
      case PostAction.allowForwarding:
        if (await _confirmAllowForwarding(context) && context.mounted) {
          await cubit.allowForwarding();
        }
      case PostAction.shorten:
        final choice = await _pickShortenChoice(context);
        if (choice == null || !context.mounted) break;
        final duration = choice.duration;
        if (duration != null) {
          await cubit.shorten(duration);
        } else if (await _confirmCloseNow(context) && context.mounted) {
          await cubit.closeNow();
        }
      case PostAction.closeNow:
        if (await _confirmCloseNow(context) && context.mounted) {
          await cubit.closeNow();
        }
      case PostAction.budRequest:
        // ⋮ opens the form immediately (D3 unlimited). Prefill: author gets
        // the root; others start blank (message action still prefills).
        final cubit = context.read<PostViewCubit>();
        final sourceId = cubit.state.beacon.author.id == cubit.myProfile.id
            ? (cubit.state.beacon.postRootMessageId ?? '')
            : '';
        await context.router.push(
          BeaconCreateRoute(parentBeaconId: id, sourceMessageId: sourceId),
        );
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

  Future<_ShortenChoice?> _pickShortenChoice(BuildContext context) {
    final l10n = L10n.of(context)!;
    final cubit = context.read<PostViewCubit>();
    final expiresAt = cubit.state.beacon.expiresAt;
    final remaining = expiresAt?.difference(cubit.now());
    return showTenturaAdaptiveSheet<_ShortenChoice>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ctx.tt.screenHPadding,
                vertical: ctx.tt.rowGap,
              ),
              child: Text(
                l10n.postShortenTitle,
                style: TenturaText.titleSmall(ctx.tt.text),
              ),
            ),
            for (final choice in _ShortenChoice.values)
              if (choice.duration == null ||
                  (remaining != null && choice.duration! < remaining))
                ListTile(
                  title: Text(switch (choice) {
                    _ShortenChoice.hour => l10n.postShortenIn1h,
                    _ShortenChoice.sixHours => l10n.postShortenIn6h,
                    _ShortenChoice.day => l10n.postShortenIn24h,
                    _ShortenChoice.closeNow => l10n.postActionCloseNow,
                  }),
                  onTap: () => Navigator.pop(ctx, choice),
                ),
          ],
        ),
      ),
    );
  }

  Future<bool> _confirmCloseNow(BuildContext context) async {
    final l10n = L10n.of(context)!;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(l10n.postCloseNowConfirmTitle),
            content: Text(l10n.postCloseNowConfirmBody),
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
                child: Text(l10n.postActionCloseNow),
              ),
            ],
          ),
        ) ??
        false;
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

/// «‹начало поста›» over «‹Автор› · N участников · 🔕»; the whole title opens
/// «О посте». The excerpt is the subject, so it gets the title line alone
/// (two lines beside a wide window) and the author moves under it (#667).
class _Title extends StatelessWidget {
  const _Title({required this.state, required this.now, required this.onTap});

  final PostViewState state;
  final DateTime now;
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
    final title = excerpt.isEmpty ? author : excerpt;
    final metaStyle = TenturaText.bodySmall(tt.textMuted);
    // Status glyphs match the meta line so two title lines fit the bar.
    final metaIconSize = metaStyle.fontSize! * (metaStyle.height ?? 1);
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
              maxLines: context.windowClass == WindowClass.compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TenturaText.titleSmall(tt.text),
            ),
            Row(
              children: [
                Flexible(
                  child: _MembersLine(
                    post: state.beacon,
                    now: now,
                    author: excerpt.isEmpty ? '' : author,
                    style: metaStyle,
                  ),
                ),
                if (muted) ...[
                  SizedBox(width: tt.tightGap),
                  Icon(
                    Icons.notifications_off_outlined,
                    size: metaIconSize,
                    color: tt.textMuted,
                    semanticLabel: l10n.postConversationMuted,
                  ),
                ],
                if (state.summary?.isPinned ?? false) ...[
                  SizedBox(width: tt.tightGap),
                  Icon(
                    Icons.push_pin_outlined,
                    size: metaIconSize,
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

/// «‹Автор› · N участников», counted from the room once it is loaded; only
/// the author until then.
class _MembersLine extends StatelessWidget {
  const _MembersLine({
    required this.post,
    required this.now,
    required this.author,
    required this.style,
  });

  final Beacon post;
  final DateTime now;

  /// Empty when the title already names the author.
  final String author;
  final TextStyle style;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<ThreadHostCubit, ThreadHostState>(
        builder: (context, _) {
          final room = context.read<ThreadHostCubit>().roomCubit;
          if (room == null) return _line(context, null);
          return BlocBuilder<RoomCubit, RoomState>(
            bloc: room,
            buildWhen: (p, c) =>
                p.participants != c.participants ||
                p.participantsLoaded != c.participantsLoaded,
            builder: (context, roomState) {
              if (!roomState.participantsLoaded) return _line(context, null);
              final count = withPostAuthor(
                roomState.participants,
                post,
              ).where((p) => p.roomAccess == RoomAccessBits.admitted).length;
              return _line(context, count);
            },
          );
        },
      );

  Widget _line(BuildContext context, int? count) {
    final l10n = L10n.of(context)!;
    final members = count == null ? '' : l10n.postHeaderMembers(count);
    final who = author.isEmpty
        ? members
        : members.isEmpty
        ? author
        : l10n.postHeaderAuthorMembers(author, members);
    final expiresAt = post.expiresAt;
    final lifetime = post.isPostArchivedAt(now)
        ? l10n.postArchivedMarker
        : expiresAt == null
        ? ''
        : postRemainingLabel(l10n, expiresAt.difference(now));
    final text = lifetime.isEmpty
        ? who
        : who.isEmpty
        ? lifetime
        : l10n.postHeaderAuthorMembers(who, lifetime);
    if (text.isEmpty) return const SizedBox.shrink();
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// ⋮: «О посте», mute and pin, then complain / leave / delete.
class _Overflow extends StatelessWidget {
  const _Overflow({
    required this.state,
    required this.lifetimeNow,
    required this.postBuddingEnabled,
    required this.onSelected,
  });

  final PostViewState state;

  /// The cubit's clock, which the screen refreshes at the Post's deadline.
  final DateTime lifetimeNow;
  final bool postBuddingEnabled;
  final ValueChanged<PostAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final now = DateTime.now();
    final summary = state.summary;
    final viewerId = context.read<PostViewCubit>().myProfile.id;
    final viewerIsAuthor = state.beacon.author.id == viewerId;
    // Only the author of an open, unexpired Post can still change its end.
    final canChangeLifetime =
        viewerIsAuthor &&
        state.beacon.status == BeaconStatus.open &&
        !state.beacon.isPostArchivedAt(lifetimeNow);
    final muted = summary?.isMutedAt(now) ?? false;
    // Any member of an open Post may bud (D3 unlimited); no own-message gate.
    bool canBud() =>
        postBuddingEnabled && state.beacon.status == BeaconStatus.open;

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
        item(
          PostAction.participants,
          Icons.people_outline,
          l10n.postMenuParticipants,
        ),
        if (muted)
          item(
            PostAction.unmute,
            Icons.notifications_active_outlined,
            summary!.mutedForever
                ? l10n.postMenuUnmuteForever
                : l10n.postMenuUnmuteUntil(
                    postMuteUntilTime(
                      summary.mutedUntil!,
                      now,
                      locale: l10n.localeName,
                    ),
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
        if (canBud())
          item(
            PostAction.budRequest,
            Icons.subdirectory_arrow_right_outlined,
            l10n.postBudAction,
          ),
        if (canChangeLifetime) ...[
          item(
            PostAction.shorten,
            Icons.timer_outlined,
            l10n.postActionShorten,
          ),
          item(
            PostAction.closeNow,
            Icons.stop_circle_outlined,
            l10n.postActionCloseNow,
          ),
        ],
        const PopupMenuDivider(),
        if (!viewerIsAuthor)
          item(PostAction.complain, Icons.flag_outlined, l10n.buttonComplaint),
        if (!_isClosed(state) && _viewerIsAddressee(context, viewerId))
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

/// A Post closed by budding is read-only: no forward, leave or other writes
/// (plan D2; the server rejects them too).
bool _isClosed(PostViewState state) =>
    state.beacon.status == BeaconStatus.closed;

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
