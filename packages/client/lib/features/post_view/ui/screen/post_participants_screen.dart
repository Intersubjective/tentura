import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/friends/ui/dialog/friend_remove_dialog.dart';
import 'package:tentura/features/profile_view/ui/bloc/profile_view_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Who is in a Post's conversation and who has not opened it yet.
class PostParticipantsScreen extends StatefulWidget {
  const PostParticipantsScreen({
    required this.beaconId,
    required this.viewerId,
    required this.participants,
    required this.forwardEdges,
    this.canForward = true,
    this.profileViewCubitFactory,
    super.key,
  });

  final String beaconId;
  final String viewerId;
  final List<BeaconParticipant> participants;
  final List<ForwardEdge> forwardEdges;
  final bool canForward;

  /// Creates the per-person cubit that answers «in contacts» and adds a
  /// contact; defaults to a real [ProfileViewCubit].
  final ProfileViewCubit Function(String id)? profileViewCubitFactory;

  @override
  State<PostParticipantsScreen> createState() => _PostParticipantsScreenState();
}

class _PostParticipantsScreenState extends State<PostParticipantsScreen> {
  final _cubits = <String, ProfileViewCubit>{};

  ProfileViewCubit _cubitFor(String id) => _cubits[id] ??=
      widget.profileViewCubitFactory?.call(id) ?? ProfileViewCubit(id: id);

  @override
  void dispose() {
    for (final cubit in _cubits.values) {
      unawaited(cubit.close());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final admitted = widget.participants
        .where((p) => p.roomAccess == RoomAccessBits.admitted)
        .toList();
    final unopened = admitted.where(_hasNotOpened).toList();
    final inConversation = admitted.where((p) => !_hasNotOpened(p)).toList();
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: tt.screenHPadding,
                vertical: tt.rowGap,
              ),
              child: Text(
                l10n.postParticipantsTitle(admitted.length),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            if (widget.canForward)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.postParticipantsForwardingOpen,
                        style: TenturaText.bodySmall(tt.textMuted),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => context.router.root.push(
                        ForwardBeaconRoute(beaconId: widget.beaconId),
                      ),
                      icon: const Icon(Icons.north_east),
                      label: Text(l10n.postParticipantsInvite),
                    ),
                  ],
                ),
              ),
            const Divider(height: 1),
            _Heading(
              l10n.postParticipantsInConversation(inConversation.length),
            ),
            for (final p in inConversation) _row(p, showContactState: true),
            if (unopened.isNotEmpty) ...[
              _Heading(l10n.postParticipantsUnopened(unopened.length)),
              for (final p in unopened) _row(p, showContactState: false),
            ],
            const Divider(height: 1),
            ListTile(
              title: Text(l10n.postParticipantsForwardsGraph),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.read<ScreenCubit>().showForwardsGraphFor(
                widget.beaconId,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The author and the viewer are always in the conversation.
  bool _hasNotOpened(BeaconParticipant p) =>
      p.lastSeenRoomAt == null &&
      p.role != BeaconParticipantRoleBits.author &&
      p.userId != widget.viewerId;

  Widget _row(BeaconParticipant p, {required bool showContactState}) {
    final isViewer = p.userId == widget.viewerId;
    final edge = widget.forwardEdges
        .where((e) => e.recipient.id == p.userId)
        .firstOrNull;
    return _PersonRow(
      participant: p,
      isViewer: isViewer,
      broughtBy: edge?.sender.shownName ?? '',
      cubit: showContactState && !isViewer ? _cubitFor(p.userId) : null,
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        tt.screenHPadding,
        tt.sectionGap,
        tt.screenHPadding,
        tt.rowGap,
      ),
      child: Text(text, style: TenturaText.bodySmall(tt.textMuted)),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.participant,
    required this.isViewer,
    required this.broughtBy,
    required this.cubit,
  });

  final BeaconParticipant participant;
  final bool isViewer;
  final String broughtBy;

  /// `null` when the row has no contact state (viewer, not opened yet).
  final ProfileViewCubit? cubit;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final muted = TenturaText.bodySmall(tt.textMuted);
    final isAuthor = participant.role == BeaconParticipantRoleBits.author;
    return InkWell(
      onTap: () => context.router.root.push(
        ProfileViewRoute(id: participant.userId),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tt.screenHPadding,
          vertical: tt.rowGap,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                isViewer
                    ? l10n.labelYou
                    : participant.displayLabel(l10n.unknownPerson),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isAuthor) Text(l10n.postParticipantAuthor, style: muted),
            if (broughtBy.isNotEmpty && !isViewer)
              Flexible(
                child: Text(
                  l10n.postParticipantBroughtBy(broughtBy),
                  style: muted,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (cubit case final cubit?)
              BlocBuilder<ProfileViewCubit, ProfileViewState>(
                bloc: cubit,
                // Trust toggle instead of an "add" button (#140).
                builder: (context, state) => Tooltip(
                  message: state.profile.isFriend
                      ? l10n.removeFromMyField
                      : l10n.trustThisUser,
                  child: Switch.adaptive(
                    value: state.profile.isFriend,
                    onChanged: (on) => on
                        ? unawaited(cubit.addFriend())
                        : unawaited(
                            FriendRemoveDialog.show(
                              context,
                              profile: state.profile,
                              onRemove: cubit.removeFriend,
                            ),
                          ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
