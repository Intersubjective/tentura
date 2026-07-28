import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_entity.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart';

/// Records a chat join system line + activity event after a new admission.
Future<void> recordBeaconRoomParticipantJoined({
  required TenturaDb db,
  required String beaconId,
  required String joinedUserId,
  required String actorUserId,
  required String admissionReason,
}) async {
  final message = await db.managers.beaconRoomMessages.createReturning(
    (o) => o(
      id: generateId('R'),
      beaconId: beaconId,
      authorId: actorUserId,
      body: const Value(''),
      semanticMarker: const Value(BeaconRoomSemanticMarker.participantJoined),
      systemPayload: Value(<String, Object?>{
        'joinedUserId': joinedUserId,
        'actorUserId': actorUserId,
        'admissionReason': admissionReason,
      }),
      createdAt: const Value.absent(),
    ),
  );

  await db.managers.beaconActivityEvents.create(
    (o) => o(
      id: Value(BeaconActivityEventEntity.newId),
      beaconId: beaconId,
      visibility: BeaconActivityEventVisibilityBits.room,
      type: BeaconActivityEventTypeBits.participantJoined,
      actorId: Value(actorUserId),
      targetUserId: Value(joinedUserId),
      sourceMessageId: Value(message.id),
      diff: Value(<String, Object?>{
        'joinedUserId': joinedUserId,
        'admissionReason': admissionReason,
      }),
      createdAt: const Value.absent(),
    ),
  );
}
