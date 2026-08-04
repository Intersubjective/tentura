import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';

BeaconParticipant? participantForUserId(
  List<BeaconParticipant> participants,
  String? userId,
) {
  if (userId == null || userId.isEmpty) return null;
  for (final p in participants) {
    if (p.userId == userId) return p;
  }
  return null;
}

Profile profileForParticipant(
  List<BeaconParticipant> participants,
  String userId, {
  Profile? viewerProfile,
}) {
  if (userId.isEmpty) return const Profile();
  if (viewerProfile != null &&
      viewerProfile.id.isNotEmpty &&
      viewerProfile.id == userId) {
    return viewerProfile;
  }
  for (final p in participants) {
    if (p.userId == userId) {
      return Profile(
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
      );
    }
  }
  // Id-only profile for avatar/identity; use [Profile.displayLabel] for UI text.
  return Profile(id: userId);
}

/// Display label for a participant lookup; never returns [userId] as text.
String participantDisplayLabel(
  List<BeaconParticipant> participants,
  String userId,
  String unknownPersonLabel, {
  Profile? viewerProfile,
}) =>
    profileForParticipant(
      participants,
      userId,
      viewerProfile: viewerProfile,
    ).displayLabel(unknownPersonLabel);

Profile profileForBeaconParticipant(
  BeaconParticipant participant, {
  Profile? viewerProfile,
}) =>
    profileForParticipant(
      [participant],
      participant.userId,
      viewerProfile: viewerProfile,
    );
