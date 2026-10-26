import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/post_people.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_state.dart';
import 'package:tentura/features/profile_view/ui/bloc/profile_view_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/post_view_cubit.dart';
import '../post_remaining_label.dart';
import 'post_action.dart';
import 'post_participants_list.dart';

/// «О посте»: everything about the Post and everything the viewer can do with
/// it, in one place (the ⋮ menu keeps only the shortcuts). Resolves to the
/// [PostAction] picked, which the Post screen runs; null when dismissed.
Future<PostAction?> showPostInfoSheet(
  BuildContext context, {
  required PostViewCubit cubit,
  required ThreadHostCubit host,
  ProfileViewCubit Function(String id)? profileViewCubitFactory,
  bool scrollToParticipants = false,
}) => showTenturaAdaptiveSheet<PostAction>(
  context: context,
  builder: (_) => PostInfoSheet(
    cubit: cubit,
    host: host,
    profileViewCubitFactory: profileViewCubitFactory,
    scrollToParticipants: scrollToParticipants,
  ),
);

class PostInfoSheet extends StatelessWidget {
  const PostInfoSheet({
    required this.cubit,
    required this.host,
    this.profileViewCubitFactory,
    this.scrollToParticipants = false,
    super.key,
  });

  /// Opened from ⋮ «Участники»: the participants are scrolled into view
  /// (#715).
  final bool scrollToParticipants;

  /// The participants block, for tests and for [scrollToParticipants].
  static const participantsKey = Key('PostInfoSheet.participants');

  final PostViewCubit cubit;

  /// Watched, not snapshotted: the room may still be opening when the sheet
  /// is, and its participants and the Leave action appear once it has.
  final ThreadHostCubit host;
  final ProfileViewCubit Function(String id)? profileViewCubitFactory;

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<PostViewCubit, PostViewState>(
        bloc: cubit,
        builder: (context, state) =>
            BlocBuilder<ThreadHostCubit, ThreadHostState>(
              bloc: host,
              builder: (context, _) {
                final room = host.roomCubit;
                if (room == null) return _body(context, state, const []);
                return BlocBuilder<RoomCubit, RoomState>(
                  bloc: room,
                  buildWhen: (p, c) => p.participants != c.participants,
                  builder: (context, roomState) =>
                      _body(context, state, roomState.participants),
                );
              },
            ),
      );

  Widget _body(
    BuildContext context,
    PostViewState state,
    List<BeaconParticipant> participants,
  ) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final lifetimeNow = cubit.now();
    final beacon = state.beacon;
    final summary = state.summary;
    final viewerId = cubit.myProfile.id;
    final isAuthor = beacon.author.id == viewerId;
    final isAddressee = participants.any(
      (p) =>
          p.userId == viewerId &&
          p.role == BeaconParticipantRoleBits.addressee &&
          p.roomAccess == RoomAccessBits.admitted,
    );
    final muted = summary?.isMutedAt(now) ?? false;
    final pinned = summary?.isPinned ?? false;
    final rootExcerpt = summary?.rootExcerpt.trim() ?? '';
    // A Post closed by budding is read-only (plan D2).
    final isClosed = beacon.status == BeaconStatus.closed;
    final canForward = beacon.viewerCanForward && !isClosed;
    void pick(PostAction action) => Navigator.of(context).pop(action);

    final muteLine = summary == null
        ? null
        : postMuteLine(
            l10n,
            mutedForever: summary.mutedForever,
            mutedUntil: summary.mutedUntil,
            now: now,
          );
    final expiresAt = beacon.expiresAt;
    final lifetimeLine = beacon.isPostArchivedAt(lifetimeNow)
        ? l10n.postArchivedMarker
        : expiresAt == null
        ? null
        : postRemainingLabel(l10n, expiresAt.difference(lifetimeNow));
    final forwardingOpen =
        beacon.forwardPolicy == BeaconForwardPolicyValue.open;

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: tt.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
              child: Row(
                children: [
                  ExcludeSemantics(
                    child: TenturaAvatar.medium(profile: beacon.author),
                  ),
                  SizedBox(width: tt.avatarTextGap),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          beacon.author.shownName,
                          style: TenturaText.titleSmall(tt.text),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${dateFormatYMD(beacon.createdAt, locale: l10n.localeName)} '
                          '${timeFormatHm(beacon.createdAt, locale: l10n.localeName)}',
                          style: TenturaText.bodySmall(tt.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (rootExcerpt.isNotEmpty)
              InkWell(
                onTap: () => pick(PostAction.scrollToRoot),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: tt.screenHPadding,
                    vertical: tt.rowGap,
                  ),
                  child: Text(
                    rootExcerpt,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: TenturaText.bodyMedium(tt.text),
                  ),
                ),
              ),
            _Fact(
              icon: forwardingOpen ? Icons.north_east : Icons.lock_outline,
              text: forwardingOpen
                  ? l10n.postInfoForwardingOpen
                  : l10n.postInfoForwardingClosed,
              action: isAuthor && !forwardingOpen && !isClosed
                  ? TextButton(
                      onPressed: () => pick(PostAction.allowForwarding),
                      child: Text(l10n.postMenuAllowForwarding),
                    )
                  : null,
            ),
            if (lifetimeLine != null)
              _Fact(icon: Icons.schedule, text: lifetimeLine),
            if (muteLine != null)
              _Fact(icon: Icons.notifications_off_outlined, text: muteLine),
            SizedBox(height: tt.rowGap),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (canForward)
                    _QuickAction(
                      icon: Icons.north_east,
                      label: l10n.postInfoActionForward,
                      onTap: () => pick(PostAction.forward),
                    ),
                  _QuickAction(
                    icon: muted
                        ? Icons.notifications_active_outlined
                        : Icons.notifications_off_outlined,
                    label: muted
                        ? l10n.postInfoActionUnmute
                        : l10n.postInfoActionMute,
                    onTap: () =>
                        pick(muted ? PostAction.unmute : PostAction.mute),
                  ),
                  _QuickAction(
                    icon: pinned ? Icons.push_pin : Icons.push_pin_outlined,
                    label: pinned
                        ? l10n.postInfoActionUnpin
                        : l10n.postInfoActionPin,
                    onTap: () =>
                        pick(pinned ? PostAction.unpin : PostAction.pin),
                  ),
                  _QuickAction(
                    icon: Icons.bubble_chart_outlined,
                    label: l10n.postInfoActionField,
                    onTap: () => pick(PostAction.showOnField),
                  ),
                ],
              ),
            ),
            SizedBox(height: tt.rowGap),
            const Divider(height: 1),
            SizedBox(height: tt.rowGap),
            _RevealOnOpen(
              key: participantsKey,
              enabled: scrollToParticipants,
              child: PostParticipantsList(
                viewerId: viewerId,
                participants: withPostAuthor(participants, beacon),
                forwardEdges: state.forwardEdges,
                // «Позвать» opens the invite dialog itself (#715).
                onInvite: canForward ? () => pick(PostAction.invite) : null,
                onForwardsGraph: () => pick(PostAction.forwardsGraph),
                profileViewCubitFactory: profileViewCubitFactory,
              ),
            ),
            const Divider(height: 1),
            if (!isAuthor)
              _ActionTile(
                icon: Icons.flag_outlined,
                label: l10n.buttonComplaint,
                color: scheme.onSurface,
                onTap: () => pick(PostAction.complain),
              ),
            if (isAddressee && !isClosed)
              _ActionTile(
                icon: Icons.logout,
                label: l10n.postMenuLeave,
                color: scheme.error,
                onTap: () => pick(PostAction.leave),
              ),
            if (isAuthor)
              _ActionTile(
                icon: Icons.delete_outline,
                label: l10n.postMenuDelete,
                color: scheme.error,
                onTap: () => pick(PostAction.delete),
              ),
          ],
        ),
      ),
    );
  }
}

/// Scrolls [child] to the top of the sheet once, after the first frame, when
/// [enabled].
class _RevealOnOpen extends StatefulWidget {
  const _RevealOnOpen({
    required this.enabled,
    required this.child,
    super.key,
  });

  final bool enabled;
  final Widget child;

  @override
  State<_RevealOnOpen> createState() => _RevealOnOpenState();
}

class _RevealOnOpenState extends State<_RevealOnOpen> {
  @override
  void initState() {
    super.initState();
    if (!widget.enabled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(Scrollable.ensureVisible(context));
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final action = this.action;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tt.screenHPadding,
        vertical: tt.tightGap,
      ),
      child: Row(
        children: [
          Icon(icon, size: tt.iconSize, color: tt.textMuted),
          SizedBox(width: tt.iconTextGap),
          Expanded(
            child: Text(text, style: TenturaText.bodySmall(tt.textMuted)),
          ),
          ?action,
        ],
      ),
    );
  }
}

/// One of the round shortcuts under the Post (Переслать / Звук / Закрепить /
/// На поле). The shortcuts share the row equally, so a narrow screen or large
/// text shortens the labels instead of overflowing.
class _QuickAction extends StatelessWidget {
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(tt.cardRadius),
          child: Padding(
            padding: EdgeInsets.all(tt.tightGap),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filledTonal(onPressed: onTap, icon: Icon(icon)),
                Text(
                  label,
                  style: TenturaText.labelSmall(tt.text),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: color),
    title: Text(label, style: TenturaText.bodyMedium(color)),
    onTap: onTap,
  );
}
