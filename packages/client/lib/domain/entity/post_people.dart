import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';

/// The room's participants with the Post's author added when they have no row
/// of their own: a Post's rows are its addressees, so the author was missing
/// from the count and the list (#417).
List<BeaconParticipant> withPostAuthor(
  List<BeaconParticipant> participants,
  Beacon post,
) {
  final author = post.author;
  if (author.id.isEmpty || participants.any((p) => p.userId == author.id)) {
    return participants;
  }
  final image = author.image;
  return [
    BeaconParticipant(
      id: '',
      beaconId: post.id,
      userId: author.id,
      role: BeaconParticipantRoleBits.author,
      status: 0,
      roomAccess: RoomAccessBits.admitted,
      createdAt: post.createdAt,
      updatedAt: post.createdAt,
      userTitle: author.shownName,
      handle: author.handle,
      userHasPicture: image != null && image.id.isNotEmpty,
      userPicHeight: image?.height ?? 0,
      userPicWidth: image?.width ?? 0,
      userBlurHash: image?.blurHash ?? '',
      userImageId: image?.id ?? '',
    ),
    ...participants,
  ];
}
