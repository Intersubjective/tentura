import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';

/// People a plan step may be assigned to (#220, owner rule: admitted only):
/// the [author], the admitted helpers ([admittedHelpers]) and every admitted
/// room member in [roomParticipants] (stewards, Post addressees). Author
/// first, no duplicates.
List<Profile> planAssignablePeople({
  required Profile author,
  required List<Profile> admittedHelpers,
  required List<BeaconParticipant> roomParticipants,
}) {
  final seen = <String>{};
  return [
    if (author.id.isNotEmpty && seen.add(author.id)) author,
    for (final p in admittedHelpers)
      if (p.id.isNotEmpty && seen.add(p.id)) p,
    for (final p in roomParticipants)
      if (p.roomAccess == RoomAccessBits.admitted &&
          p.userId.isNotEmpty &&
          seen.add(p.userId))
        Profile(
          id: p.userId,
          displayName: p.userTitle,
          handle: p.handle,
          image: p.userHasPicture && p.userImageId.isNotEmpty
              ? ImageEntity(
                  id: p.userImageId,
                  authorId: p.userId,
                  blurHash: p.userBlurHash,
                  height: p.userPicHeight,
                  width: p.userPicWidth,
                )
              : null,
        ),
  ];
}
