import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';

/// Room participant rows filtered for the Beacon view **People** lens (Phase 4).
///
/// Server only returns [participants] when the viewer may use the room API;
/// when the list is empty / unavailable this returns an empty list.
List<BeaconParticipant> beaconParticipantsVisibleForViewer({
  required List<BeaconParticipant> participants,
  required String viewerUserId,
  required String authorUserId,
}) {
  BeaconParticipant? mine;
  for (final p in participants) {
    if (p.userId == viewerUserId) {
      mine = p;
      break;
    }
  }

  final viewerAuthor = viewerUserId == authorUserId;
  final viewerSteward = mine?.role == BeaconParticipantRoleBits.steward;
  final viewerAdmitted = mine?.roomAccess == RoomAccessBits.admitted;
  final fullLens =
      viewerAdmitted || viewerAuthor || viewerSteward;

  final filtered = participants
      .where((p) => p.roomAccess != RoomAccessBits.left);

  if (fullLens) {
    final list = filtered.toList(growable: false)
      ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
    return list;
  }

  bool pubLens(BeaconParticipant p) {
    if (p.userId == viewerUserId) return true;
    final role = p.role;
    return role == BeaconParticipantRoleBits.author ||
        role == BeaconParticipantRoleBits.steward ||
        role == BeaconParticipantRoleBits.forwarder;
  }

  final list = filtered.where(pubLens).toList(growable: false)
    ..sort((a, b) => a.updatedAt.compareTo(b.updatedAt));
  return list;
}

/// Best-effort display name: author, then [userIdToKnownTitle] (e.g. commitments), else id.
String participantDisplayTitle({
  required BeaconParticipant participant,
  required Beacon beacon,
  required Map<String, String> userIdToKnownTitle,
}) {
  if (participant.userId == beacon.author.id) {
    return beacon.author.title;
  }
  final t = userIdToKnownTitle[participant.userId];
  if (t != null && t.trim().isNotEmpty) return t.trim();
  return participant.userId.length <= 10
      ? participant.userId
      : '${participant.userId.substring(0, 8)}…';
}
