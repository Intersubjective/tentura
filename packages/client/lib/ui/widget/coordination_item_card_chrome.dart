import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/ui/widget/coordination_log_row_chrome.dart';

/// Items tab card header lead: `[dst avatar?] [←] [src avatar]`.
Widget coordinationItemCardAvatarTrail({
  BeaconParticipant? source,
  BeaconParticipant? target,
}) {
  if (source == null && target == null) return const SizedBox.shrink();

  final children = <Widget>[];
  if (target != null) {
    children.add(coordinationLogParticipantAvatar(target));
  }
  if (target != null && source != null) {
    children.addAll([
      const SizedBox(width: 2),
      const Icon(Icons.arrow_left_alt, size: kCoordinationLogAvatarSize),
    ]);
  }
  if (source != null) {
    children.add(coordinationLogParticipantAvatar(source));
  }

  return Row(
    mainAxisSize: MainAxisSize.min,
    children: children,
  );
}
