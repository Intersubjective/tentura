import 'package:tentura_server/data/database/tentura_db.dart' as db;
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';

extension CoordinationItemRowMapper on db.CoordinationItem {
  CoordinationItemRecord toRecord() => CoordinationItemRecord(
        id: id,
        beaconId: beaconId,
        kind: kind,
        status: status,
        title: title,
        body: body,
        creatorId: creatorId,
        targetPersonId: targetPersonId,
        acceptedById: acceptedById,
        targetItemId: targetItemId,
        targetMessageId: targetMessageId,
        linkedMessageId: linkedMessageId,
        linkedParentItemId: linkedParentItemId,
        ordering: ordering,
        source: source,
        published: published,
        createdAt: createdAt.dateTime,
        updatedAt: updatedAt.dateTime,
        publishedAt: publishedAt?.dateTime,
        resolvedAt: resolvedAt?.dateTime,
        cancelledAt: cancelledAt?.dateTime,
        staleAt: staleAt?.dateTime,
        lastRemindedAt: lastRemindedAt?.dateTime,
        staleAfterDays: staleAfterDays,
      );
}

extension BeaconRoomMessageRowMapper on db.BeaconRoomMessage {
  BeaconRoomMessageRecord toRecord() => BeaconRoomMessageRecord(
        id: id,
        beaconId: beaconId,
        authorId: authorId,
        body: body,
        replyToMessageId: replyToMessageId,
        threadItemId: threadItemId,
        linkedPollingId: linkedPollingId,
        semanticMarker: semanticMarker,
        systemPayload: systemPayload == null
            ? null
            : Map<String, Object?>.from(systemPayload! as Map),
        createdAt: createdAt.dateTime,
        editedAt: editedAt?.dateTime,
        mentions: List<String>.from(mentions),
      );
}

extension BeaconRoomStateRowMapper on db.BeaconRoomState {
  BeaconRoomStateRecord toRecord() => BeaconRoomStateRecord(
        beaconId: beaconId,
        currentLine: currentLine,
        openBlockerId: openBlockerId,
        lastRoomMeaningfulChange: lastRoomMeaningfulChange,
        updatedAt: updatedAt.dateTime,
        updatedBy: updatedBy,
      );
}

extension BeaconParticipantRowMapper on db.BeaconParticipant {
  BeaconParticipantRecord toRecord() => BeaconParticipantRecord(
        id: id,
        beaconId: beaconId,
        userId: userId,
        role: role,
        status: status,
        roomAccess: roomAccess,
        nextMoveText: nextMoveText,
        nextMoveStatus: nextMoveStatus,
        nextMoveSource: nextMoveSource,
        linkedMessageId: linkedMessageId,
        offerNote: offerNote,
        createdAt: createdAt.dateTime,
        updatedAt: updatedAt.dateTime,
      );
}

extension BeaconRoomMessageAttachmentRowMapper on db.BeaconRoomMessageAttachment {
  BeaconRoomMessageAttachmentRecord toRecord() =>
      BeaconRoomMessageAttachmentRecord(
        id: id,
        messageId: messageId,
        kind: kind,
        imageId: imageId?.uuid,
        fileUrl: fileUrl,
        fileName: fileName,
        mime: mime,
        sizeBytes: sizeBytes,
        width: width,
        height: height,
        position: position,
      );
}

extension PollingRowMapper on db.Polling {
  PollingVotePolicy toVotePolicy() => PollingVotePolicy(
        pollType: pollType,
        allowRevote: allowRevote,
      );
}
