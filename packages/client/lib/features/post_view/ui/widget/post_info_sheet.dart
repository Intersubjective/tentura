import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_state.dart';
import 'package:tentura/features/inbox/ui/bloc/posts_cubit.dart';
import 'package:tentura/features/profile_view/ui/bloc/profile_view_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../bloc/post_view_cubit.dart';
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
}) => showTenturaAdaptiveSheet<PostAction>(
  context: context,
  builder: (_) => PostInfoSheet(
    cubit: cubit,
    host: host,
    profileViewCubitFactory: profileViewCubitFactory,
  ),
);

class PostInfoSheet extends StatelessWidget {
  const PostInfoSheet({
    required this.cubit,
    required this.host,
    this.profileViewCubitFactory,
    super.key,
  });

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
    final canForward = beacon.viewerCanForward;
    void pick(PostAction action) => Navigator.of(context).pop(action);

    final muteLine = summary == null
        ? null
        : postMuteLine(
            l10n,
            mutedForever: summary.mutedForever,
            mutedUntil: summary.mutedUntil,
            now: now,
          );
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
                          '${dateFormatYMD(beacon.createdAt)} '
                          '${timeFormatHm(beacon.createdAt)}',
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
              action: isAuthor && !forwardingOpen
                  ? TextButton(
                      onPressed: () => pick(PostAction.allowForwarding),
                      child: Text(l10n.postMenuAllowForwarding),
                    )
                  : null,
            ),
            _Fact(
              icon: pinned ? Icons.push_pin_outlined : Icons.schedule,
              text: _activityLine(
                l10n,
                pinned: pinned,
                lastActivityAt:
                    summary?.lastActivityAt ??
                    beacon.lastActivityAt ??
                    beacon.createdAt,
                now: now,
              ),
            ),
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
            PostParticipantsList(
              viewerId: viewerId,
              participants: participants,
              forwardEdges: state.forwardEdges,
              onInvite: canForward ? () => pick(PostAction.forward) : null,
              onForwardsGraph: () => pick(PostAction.forwardsGraph),
              profileViewCubitFactory: profileViewCubitFactory,
            ),
            const Divider(height: 1),
            if (isAuthor)
              _ActionTile(
                icon: Icons.change_circle_outlined,
                label: l10n.postMenuConvertToRequest,
                color: scheme.onSurface,
                onTap: () => pick(PostAction.convertToRequest),
              ),
            if (!isAuthor)
              _ActionTile(
                icon: Icons.flag_outlined,
                label: l10n.buttonComplaint,
                color: scheme.onSurface,
                onTap: () => pick(PostAction.complain),
              ),
            if (isAddressee)
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

  /// How long the Post stays in «Сейчас» before it goes quiet (72 h after the
  /// last activity), or that a pin keeps it there.
  static String _activityLine(
    L10n l10n, {
    required bool pinned,
    required DateTime lastActivityAt,
    required DateTime now,
  }) {
    if (pinned) return l10n.postInfoPinned;
    final left = lastActivityAt.add(PostsCubit.quietAfter).difference(now);
    if (left <= Duration.zero) return l10n.postInfoQuiet;
    if (left.inHours >= 24) return l10n.postInfoActiveDays(left.inDays);
    return l10n.postInfoActiveHours(left.inHours < 1 ? 1 : left.inHours);
  }
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
