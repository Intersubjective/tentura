import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';

/// Log tab / item card header — avatar diameter (matches beacon activity log).
const kCoordinationLogAvatarSize = 20.0;

/// Log tab / item card header — semantic event icon size.
const kCoordinationLogEventIconSize = 22.0;

Profile profileFromBeaconParticipant(BeaconParticipant p) => Profile(
      id: p.userId,
      title: p.userTitle,
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

/// Leading segment: [eventIcon] alone if no actor; otherwise
/// `[actor avatar] [eventIcon] [target avatar?]`.
Widget coordinationLogLeadRow({
  required Widget eventIcon,
  BeaconParticipant? actor,
  BeaconParticipant? target,
}) {
  if (actor == null) return eventIcon;

  final actorProfile = profileFromBeaconParticipant(actor);
  final actorAvatar = ClipOval(
    child: AvatarRated(
      profile: actorProfile,
      size: kCoordinationLogAvatarSize,
      withRating: false,
    ),
  );

  final children = <Widget>[
    eventIcon,
    const SizedBox(width: 2),
    actorAvatar,
    const Icon(Icons.arrow_right_alt, size: kCoordinationLogAvatarSize),
  ];

  if (target != null) {
    final targetProfile = profileFromBeaconParticipant(target);
    children.add(
      ClipOval(
        child: AvatarRated(
          profile: targetProfile,
          size: kCoordinationLogAvatarSize,
          withRating: false,
        ),
      ),
    );
  }

  return Row(
    mainAxisSize: MainAxisSize.min,
    children: children,
  );
}

String coordinationLogTimestampLabel(DateTime utc) {
  final local = utc.toLocal();
  return '${dateFormatYMD(local)} ${timeFormatHm(local)}';
}
