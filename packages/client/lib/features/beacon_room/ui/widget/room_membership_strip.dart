import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon_room/ui/util/admitted_chat_members.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/coordination_log_row_chrome.dart';

/// Persistent header strip: overlapping avatars + "Shared with N people".
class RoomMembershipStrip extends StatelessWidget {
  const RoomMembershipStrip({
    required this.participants,
    required this.beaconAuthorId,
    this.onOpenPeopleTab,
    super.key,
  });

  final List<BeaconParticipant> participants;

  final String beaconAuthorId;

  final VoidCallback? onOpenPeopleTab;

  static const double _avatarSize = 28;

  static const double _overlap = 8;

  static const double _minTapHeight = 48;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final members = admittedChatMembers(
      participants: participants,
      beaconAuthorId: beaconAuthorId,
    );
    if (members.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wc = windowClassForWidth(constraints.maxWidth);
        final maxVisible = switch (wc) {
          WindowClass.compact => 3,
          WindowClass.regular => 4,
          WindowClass.expanded => 5,
        };
        final visible = members.take(maxVisible).toList();
        final overflow = members.length - visible.length;
        final stackWidth = _avatarSize +
            (visible.length + (overflow > 0 ? 1 : 0) - 1) * (_avatarSize - _overlap);

        final content = Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tt.screenHPadding,
            vertical: tt.tightGap,
          ),
          child: Row(
            children: [
              SizedBox(
                width: stackWidth,
                height: _avatarSize,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    for (var i = 0; i < visible.length; i++)
                      Positioned(
                        left: i * (_avatarSize - _overlap),
                        child: _MemberAvatar(
                          participant: visible[i],
                          beaconAuthorId: beaconAuthorId,
                        ),
                      ),
                    if (overflow > 0)
                      Positioned(
                        left: visible.length * (_avatarSize - _overlap),
                        child: _OverflowBadge(count: overflow),
                      ),
                  ],
                ),
              ),
              SizedBox(width: tt.iconTextGap),
              Expanded(
                child: TenturaMetaText(
                  l10n.beaconRoomSharedWithCount(members.length),
                ),
              ),
              if (onOpenPeopleTab != null)
                Icon(
                  Icons.chevron_right_rounded,
                  size: tt.iconSize,
                  color: tt.textMuted,
                ),
            ],
          ),
        );

        if (onOpenPeopleTab == null) {
          return content;
        }

        return Semantics(
          button: true,
          label: l10n.beaconRoomSharedWithCountAccessibility(members.length),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onOpenPeopleTab,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: _minTapHeight),
                child: content,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MemberAvatar extends StatelessWidget {
  const _MemberAvatar({
    required this.participant,
    required this.beaconAuthorId,
  });

  final BeaconParticipant participant;

  final String beaconAuthorId;

  @override
  Widget build(BuildContext context) {
    final profile = profileFromBeaconParticipant(participant);
    final isAuthor =
        participant.userId == beaconAuthorId ||
        participant.role == BeaconParticipantRoleBits.author;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: 2,
        ),
      ),
      child: TenturaAvatar.tiny(
        profile: profile,
        size: RoomMembershipStrip._avatarSize,
        showAuthorStar: isAuthor,
      ),
    );
  }
}

class _OverflowBadge extends StatelessWidget {
  const _OverflowBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: RoomMembershipStrip._avatarSize,
      height: RoomMembershipStrip._avatarSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.surface, width: 2),
      ),
      child: Text(
        '+$count',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
