import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/ui/widget/coordination_log_row_chrome.dart';

/// Items tab card header trail: `[src avatar] [→] [dst avatar?]`.
Widget coordinationItemCardAvatarTrail({
  BeaconParticipant? source,
  BeaconParticipant? target,
}) {
  if (source == null && target == null) return const SizedBox.shrink();

  final children = <Widget>[];
  if (source != null) {
    children.add(coordinationLogParticipantAvatar(source));
  }
  if (source != null && target != null) {
    children.addAll([
      const SizedBox(width: 2),
      const Icon(
        Icons.arrow_right_alt,
        size: kCoordinationLogAvatarSize,
      ),
    ]);
  }
  if (target != null) {
    children.add(coordinationLogParticipantAvatar(target));
  }

  return Row(
    mainAxisSize: MainAxisSize.min,
    children: children,
  );
}
