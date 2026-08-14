import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';

/// Pure filter for room-chat `@` completion hints.
///
/// Returns admitted participants with a non-empty handle whose handle or
/// display title contains [query] (case-insensitive). Empty [query] (user typed
/// only `@`) returns all eligible participants. Never auto-selects.
List<BeaconParticipant> participantsMatchingMentionQuery({
  required Iterable<BeaconParticipant> participants,
  required String query,
}) {
  final q = query.trim().toLowerCase();
  return [
    for (final p in participants)
      if (p.roomAccess == RoomAccessBits.admitted &&
          p.handle.isNotEmpty &&
          (q.isEmpty ||
              p.handle.toLowerCase().contains(q) ||
              p.userTitle.toLowerCase().contains(q)))
        p,
  ];
}
