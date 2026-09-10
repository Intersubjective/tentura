import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/exception.dart';

/// Author, steward, or admitted room member may create coordination drafts/items.
Future<void> ensureCanCoordinateOnBeacon({
  required BeaconRoomRepositoryPort room,
  required String beaconId,
  required String userId,
}) async {
  if (await room.isBeaconAuthor(beaconId: beaconId, userId: userId)) {
    return;
  }
  if (await room.isBeaconSteward(beaconId: beaconId, userId: userId)) {
    return;
  }
  final p = await room.findParticipant(beaconId: beaconId, userId: userId);
  if (p?.roomAccess == RoomAccessBits.admitted) {
    return;
  }
  throw const BeaconCreateException(
    description: 'You must be an admitted beacon participant to coordinate',
  );
}
