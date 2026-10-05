import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';

/// People a plan step may be assigned to (#220, owner rule: admitted only):
/// the author, admitted helpers and every admitted room member (stewards,
/// Post addressees). Author first, no duplicates.
List<Profile> beaconPlanAdmittedPeople(BeaconViewState state) {
  final seen = <String>{};
  final author = state.beacon.author;
  final roster = state.admittedHelpersLoaded
      ? state.admittedHelperRoster
      : state.beacon.admittedHelperUsers;
  return [
    if (author.id.isNotEmpty && seen.add(author.id)) author,
    for (final p in roster)
      if (p.id.isNotEmpty && seen.add(p.id)) p,
    for (final p in state.roomParticipants)
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
