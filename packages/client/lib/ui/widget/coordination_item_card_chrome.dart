import 'package:flutter/material.dart';

import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/widget/coordination_log_row_chrome.dart';
import 'package:tentura/ui/widget/coordination_participant_lookup.dart';

/// Items tab card header trail: `[src avatar] [→] [dst avatar?]`.
Widget coordinationItemCardAvatarTrail({
  BeaconParticipant? source,
  BeaconParticipant? target,
  double? avatarSize,
}) {
  return coordinationItemProfileAvatarTrail(
    source: source != null ? profileFromBeaconParticipant(source) : null,
    target: target != null ? profileFromBeaconParticipant(target) : null,
    avatarSize: avatarSize,
  );
}

/// Profile-based directed trail for room footers and timeline bars.
Widget coordinationItemProfileAvatarTrail({
  Profile? source,
  Profile? target,
  double? avatarSize,
}) {
  if (source == null && target == null) return const SizedBox.shrink();

  final arrowSize = avatarSize ?? kCoordinationLogAvatarSize;
  final children = <Widget>[];
  if (source != null) {
    children.add(_coordinationTrailAvatar(source, avatarSize));
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
    children.add(_coordinationTrailAvatar(target, avatarSize));
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
}) {
  final source = creatorId.trim().isEmpty
      ? null
      : profileForParticipant(participants, creatorId.trim());
  final targetId = targetPersonId?.trim();
  final target = targetId != null && targetId.isNotEmpty
      ? profileForParticipant(participants, targetId)
      : null;
  return coordinationItemProfileAvatarTrail(
    source: source,
    target: target,
    avatarSize: avatarSize,
  );
}

Widget _coordinationTrailAvatar(Profile profile, double? avatarSize) {
  if (avatarSize != null) {
    return TenturaAvatar.tiny(profile: profile, size: avatarSize);
  }
  return TenturaAvatar.tiny(profile: profile);
}
