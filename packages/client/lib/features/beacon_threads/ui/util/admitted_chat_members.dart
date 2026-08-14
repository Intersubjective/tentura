import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';

/// Participants who can read the shared request chat.
List<BeaconParticipant> admittedChatMembers({
  required List<BeaconParticipant> participants,
  required String beaconAuthorId,
}) {
  final admitted = participants
      .where((p) => p.roomAccess == RoomAccessBits.admitted)
      .toList();
  if (beaconAuthorId.isEmpty) {
    return _sortChatMembers(admitted, beaconAuthorId);
  }
  final hasAuthor = admitted.any((p) => p.userId == beaconAuthorId);
  if (hasAuthor) {
    return _sortChatMembers(admitted, beaconAuthorId);
  }
  final authorRow = participants
      .where(
        (p) =>
            p.userId == beaconAuthorId ||
            p.role == BeaconParticipantRoleBits.author,
      )
      .firstOrNull;
  if (authorRow == null) {
    return _sortChatMembers(admitted, beaconAuthorId);
  }
  return _sortChatMembers([...admitted, authorRow], beaconAuthorId);
}

List<BeaconParticipant> _sortChatMembers(
  List<BeaconParticipant> members,
  String beaconAuthorId,
) {
  final copy = List<BeaconParticipant>.from(members);
  copy.sort((a, b) {
    int rank(BeaconParticipant p) {
      if (p.userId == beaconAuthorId ||
          p.role == BeaconParticipantRoleBits.author) {
        return 0;
      }
      if (p.role == BeaconParticipantRoleBits.steward) {
        return 1;
      }
      return 2;
    }

    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    return a.userTitle.toLowerCase().compareTo(b.userTitle.toLowerCase());
  });
  return copy;
}
