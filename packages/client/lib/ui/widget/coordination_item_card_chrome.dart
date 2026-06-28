import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/widget/coordination_log_row_chrome.dart';
import 'package:tentura/ui/widget/coordination_participant_lookup.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';

/// Items tab card header trail: `[src avatar] [→] [dst avatar?]`.
Widget coordinationItemCardAvatarTrail({
  BeaconParticipant? source,
  BeaconParticipant? target,
  double? avatarSize,
  Profile? viewerProfile,
}) {
  return coordinationItemProfileAvatarTrail(
    source: source != null
        ? profileForBeaconParticipant(source, viewerProfile: viewerProfile)
        : null,
    target: target != null
        ? profileForBeaconParticipant(target, viewerProfile: viewerProfile)
        : null,
    avatarSize: avatarSize,
    viewerProfile: viewerProfile,
  );
}

/// Like [coordinationItemCardAvatarTrail] but resolves the signed-in viewer profile.
Widget coordinationItemCardAvatarTrailWithViewer({
  BeaconParticipant? source,
  BeaconParticipant? target,
  double? avatarSize,
}) =>
    BlocBuilder<ProfileCubit, ProfileState>(
      buildWhen: (p, c) => p.profile.id != c.profile.id,
      builder: (context, state) => coordinationItemCardAvatarTrail(
        source: source,
        target: target,
        avatarSize: avatarSize,
        viewerProfile: state.profile,
      ),
    );

/// Profile-based directed trail for room footers and timeline bars.
Widget coordinationItemProfileAvatarTrail({
  Profile? source,
  Profile? target,
  double? avatarSize,
  Profile? viewerProfile,
}) {
  if (source == null && target == null) return const SizedBox.shrink();

  final arrowSize = avatarSize ?? kCoordinationLogAvatarSize;
  final children = <Widget>[];
  if (source != null) {
    children.add(_coordinationTrailAvatar(source, avatarSize, viewerProfile));
  }
  if (source != null && target != null) {
    children.addAll([
      const SizedBox(width: 2),
      Icon(
        Icons.arrow_right_alt,
        size: arrowSize,
      ),
    ]);
  }
  if (target != null) {
    children.add(_coordinationTrailAvatar(target, avatarSize, viewerProfile));
  }

  final trail = Row(
    mainAxisSize: MainAxisSize.min,
    children: children,
  );

  final sourceName = source?.displayName.trim();
  final targetName = target?.displayName.trim();
  if (sourceName != null &&
      sourceName.isNotEmpty &&
      targetName != null &&
      targetName.isNotEmpty) {
    return Semantics(
      label: 'From $sourceName to $targetName',
      child: trail,
    );
  }
  if (sourceName != null && sourceName.isNotEmpty) {
    return Semantics(label: sourceName, child: trail);
  }
  return trail;
}

/// Resolves beacon participants and builds a directed avatar trail.
Widget coordinationDirectedAvatarTrailForItem({
  required List<BeaconParticipant> participants,
  required String creatorId,
  String? targetPersonId,
  double? avatarSize,
}) =>
    BlocBuilder<ProfileCubit, ProfileState>(
      buildWhen: (p, c) => p.profile.id != c.profile.id,
      builder: (context, state) {
        final viewerProfile = state.profile;
        final source = creatorId.trim().isEmpty
            ? null
            : profileForParticipant(
                participants,
                creatorId.trim(),
                viewerProfile: viewerProfile,
              );
        final targetId = targetPersonId?.trim();
        final target = targetId != null && targetId.isNotEmpty
            ? profileForParticipant(
                participants,
                targetId,
                viewerProfile: viewerProfile,
              )
            : null;
        return coordinationItemProfileAvatarTrail(
          source: source,
          target: target,
          avatarSize: avatarSize,
          viewerProfile: viewerProfile,
        );
      },
    );

Widget _coordinationTrailAvatar(
  Profile profile,
  double? avatarSize,
  Profile? viewerProfile,
) {
  final avatar = avatarSize != null
      ? SelfAwareAvatar.tiny(profile: profile, size: avatarSize)
      : SelfAwareAvatar.tiny(profile: profile);
  return avatar;
}
