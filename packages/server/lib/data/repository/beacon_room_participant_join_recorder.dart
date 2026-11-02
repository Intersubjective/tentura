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
  // Snapshot of the helper's offer at admission time, stored in the line
  // itself so later edits or a withdrawal never change the quote.
  final offer = await db.managers.beaconHelpOffers
      .filter((o) => o.beaconId.id(beaconId) & o.userId.id(joinedUserId))
      .getSingleOrNull();
  final participant = await db.managers.beaconParticipants
      .filter((o) => o.beaconId.id(beaconId) & o.userId.id(joinedUserId))
      .getSingleOrNull();
  final offerNote = [offer?.message, participant?.offerNote]
      .map((t) => t?.trim())
      .firstWhere((t) => t != null && t.isNotEmpty, orElse: () => null);

  final message = await db.managers.beaconRoomMessages.createReturning(
    (o) => o(
      id: generateId('R'),
      beaconId: beaconId,
      authorId: Value(actorUserId),
      body: const Value(''),
      semanticMarker: const Value(BeaconRoomSemanticMarker.participantJoined),
      systemPayload: Value(<String, Object?>{
        'joinedUserId': joinedUserId,
        'actorUserId': actorUserId,
        'admissionReason': admissionReason,
        'offerNote': ?offerNote,
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
