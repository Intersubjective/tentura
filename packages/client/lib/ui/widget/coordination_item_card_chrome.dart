import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/ui/widget/coordination_log_row_chrome.dart';

/// Items tab card: `[src avatar] [→] [dst avatar?]` after icon and type label.
Widget coordinationItemCardAvatarTrail({
  BeaconParticipant? source,
  BeaconParticipant? target,
}) {
  if (source == null) return const SizedBox.shrink();

  final children = <Widget>[
    coordinationLogParticipantAvatar(source),
  ];
  if (target != null) {
    children.addAll([
      const SizedBox(width: 2),
      const Icon(Icons.arrow_right_alt, size: kCoordinationLogAvatarSize),
      coordinationLogParticipantAvatar(target),
    ]);
  }

  return Row(
    mainAxisSize: MainAxisSize.min,
    children: children,
  );
}
