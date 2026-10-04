import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/profile_view/ui/bloc/profile_view_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/coordination_participant_lookup.dart';

/// Who is in a Post's conversation and who has not opened it yet (M5): a
/// section of the «О посте» sheet, not a scrollable of its own.
class PostParticipantsList extends StatefulWidget {
  const PostParticipantsList({
    required this.viewerId,
    required this.participants,
    required this.forwardEdges,
    required this.onForwardsGraph,
    this.onInvite,
    this.profileViewCubitFactory,
    super.key,
  });

  final String viewerId;
  final List<BeaconParticipant> participants;
  final List<ForwardEdge> forwardEdges;

  /// «Как пост дошёл до людей».
  final VoidCallback onForwardsGraph;

  /// «Позвать»; null when the viewer may not forward the Post.
  final VoidCallback? onInvite;

  /// Creates the per-person cubit that answers «in contacts» and adds a
  /// contact; defaults to a real [ProfileViewCubit].
  final ProfileViewCubit Function(String id)? profileViewCubitFactory;

  @override
  State<PostParticipantsList> createState() => _PostParticipantsListState();
}

class _PostParticipantsListState extends State<PostParticipantsList> {
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
    final onInvite = widget.onInvite;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  l10n.postParticipantsTitle(admitted.length),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (onInvite != null)
                TextButton.icon(
                  onPressed: onInvite,
                  icon: const Icon(Icons.person_add_alt_outlined),
                  label: Text(l10n.postParticipantsInvite),
                ),
            ],
          ),
        ),
        _Heading(l10n.postParticipantsInConversation(inConversation.length)),
        for (final p in inConversation) _row(p, showContactState: true),
        if (unopened.isNotEmpty) ...[
          _Heading(l10n.postParticipantsUnopened(unopened.length)),
          for (final p in unopened) _row(p, showContactState: false),
        ],
        ListTile(
          leading: const Icon(Icons.account_tree_outlined),
          title: Text(l10n.postParticipantsForwardsGraph),
          trailing: const Icon(Icons.chevron_right),
          onTap: widget.onForwardsGraph,
        ),
      ],
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
      profile: profileForParticipant(widget.participants, p.userId),
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
        tt.rowGap,
        tt.screenHPadding,
        tt.tightGap,
      ),
      child: Text(text, style: TenturaText.bodySmall(tt.textMuted)),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.participant,
    required this.profile,
    required this.isViewer,
    required this.broughtBy,
    required this.cubit,
  });

  final BeaconParticipant participant;
  final Profile profile;
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
    final note = isAuthor
        ? l10n.postParticipantAuthor
        : broughtBy.isNotEmpty && !isViewer
        ? l10n.postParticipantBroughtBy(broughtBy)
        : '';
    return InkWell(
      onTap: () => context.router.root.push(
        ProfileViewRoute(id: participant.userId),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tt.screenHPadding,
          vertical: tt.tightGap,
        ),
        child: Row(
          children: [
            ExcludeSemantics(child: TenturaAvatar.small(profile: profile)),
            SizedBox(width: tt.avatarTextGap),
            Expanded(
              child: Text(
                isViewer
                    ? l10n.labelYou
                    : participant.displayLabel(l10n.unknownPerson),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (note.isNotEmpty)
              Flexible(
                child: Text(
                  note,
                  style: muted,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (cubit case final cubit?)
              BlocBuilder<ProfileViewCubit, ProfileViewState>(
                bloc: cubit,
                builder: (context, state) => state.profile.isFriend
                    ? Text(l10n.postParticipantInContacts, style: muted)
                    : TextButton(
                        onPressed: cubit.addFriend,
                        child: Text(l10n.postParticipantAddToContacts),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
