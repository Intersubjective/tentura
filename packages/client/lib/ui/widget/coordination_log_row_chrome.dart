import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';

/// Log tab row — avatar diameter.
const kCoordinationLogAvatarSize = 20.0;

/// Log tab row — semantic event icon size.
const kCoordinationLogEventIconSize = 22.0;

Profile profileFromBeaconParticipant(BeaconParticipant p) => Profile(
      id: p.userId,
      displayName: p.userTitle,
      image: p.userHasPicture
          ? ImageEntity(
              id: p.userImageId,
              authorId: p.userId,
              blurHash: p.userBlurHash,
              height: p.userPicHeight,
              width: p.userPicWidth,
            )
          : null,
    );

Widget coordinationLogParticipantAvatar(BeaconParticipant participant) =>
    ClipOval(
      child: AvatarRated(
        profile: profileFromBeaconParticipant(participant),
        size: kCoordinationLogAvatarSize,
        withRating: false,
      ),
    );

/// Log tab leading segment: `[src avatar] [icon] [dst avatar?]`.
Widget coordinationLogTabLeadRow({
  required Widget eventIcon,
  BeaconParticipant? actor,
  BeaconParticipant? target,
}) {
  if (actor == null) return eventIcon;

  final children = <Widget>[
    coordinationLogParticipantAvatar(actor),
    Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: eventIcon,
    ),
  ];

  if (target != null) {
    children.add(coordinationLogParticipantAvatar(target));
  }

  return Row(
    mainAxisSize: MainAxisSize.min,
    children: children,
  );
}

/// Body snippet for log rows: `diffJson.body` / `diffJson.title`, else [fallback].
String coordinationLogEventBodySnippet({
  required BeaconActivityEvent event,
  required String fallback,
}) {
  final fromDiff = _bodyFromDiffJson(event.diffJson);
  if (fromDiff != null && fromDiff.isNotEmpty) return fromDiff;
  return fallback;
}

String? _bodyFromDiffJson(String? diffJson) {
  if (diffJson == null || diffJson.trim().isEmpty) return null;
  try {
    final decoded = jsonDecode(diffJson);
    if (decoded is! Map) return null;
    final body = decoded['body'];
    if (body is String && body.trim().isNotEmpty) return body.trim();
    final title = decoded['title'];
    if (title is String && title.trim().isNotEmpty) return title.trim();
  } on Object {
    return null;
  }
  return null;
}

String coordinationLogTimestampLabel(DateTime utc) {
  final local = utc.toLocal();
  return '${dateFormatYMD(local)} ${timeFormatHm(local)}';
}
