import 'dart:typed_data';

import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../../data/repository/beacon_blocker_repository.dart';
import '../../data/repository/beacon_fact_card_repository.dart';
import '../../data/repository/beacon_room_repository.dart';

@singleton
final class BeaconRoomCase extends UseCaseBase {
  BeaconRoomCase(
    this._room,
    this._factCards,
    this._blockers, {
    required super.env,
    required super.logger,
  });

  final BeaconRoomRepository _room;

  final BeaconFactCardRepository _factCards;

  final BeaconBlockerRepository _blockers;

  Stream<String> get beaconRoomRefresh => _room.beaconRoomRefresh;

  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
  }) =>
      _room.fetchMessages(beaconId: beaconId, beforeIso: beforeIso);

  Future<List<BeaconParticipant>> fetchParticipants(String beaconId) =>
      _room.fetchParticipants(beaconId);

  Future<void> createMessage({
    required String beaconId,
    required String body,
    String? replyToMessageId,
    List<RoomPendingUpload> uploads = const [],
  }) async {
    if (body.trim().isEmpty && uploads.isEmpty) {
      return;
    }
    final first = uploads.isNotEmpty ? uploads.first : null;
    final extras =
        uploads.length > 1 ? uploads.sublist(1) : const <RoomPendingUpload>[];
    final messageId = await _room.createMessage(
      beaconId: beaconId,
      body: body,
      replyToMessageId: replyToMessageId,
      firstAttachment: first,
    );
    for (final u in extras) {
      await _room.addMessageAttachment(
        beaconId: beaconId,
        messageId: messageId,
        upload: u,
      );
    }
  }

  Future<Uint8List> downloadRoomAttachment(String attachmentId) =>
      _room.downloadRoomAttachmentBytes(attachmentId);

  Future<bool> participantOfferHelp({
    required String beaconId,
    required String note,
  }) =>
      _room.participantOfferHelp(beaconId: beaconId, note: note);

  Future<bool> admit({
    required String beaconId,
    required String participantUserId,
  }) =>
      _room.admit(beaconId: beaconId, participantUserId: participantUserId);

  Future<bool> promoteSteward({
    required String beaconId,
    required String stewardUserId,
  }) =>
      _room.promoteSteward(beaconId: beaconId, stewardUserId: stewardUserId);

  Future<bool> toggleReaction({
    required String beaconId,
    required String messageId,
    required String emoji,
  }) =>
      _room.toggleReaction(
        beaconId: beaconId,
        messageId: messageId,
        emoji: emoji,
      );

  Future<BeaconRoomState> fetchBeaconRoomState(String beaconId) =>
      _room.fetchBeaconRoomState(beaconId);

  Future<bool> updateRoomPlan({
    required String beaconId,
    required String currentPlan,
  }) =>
      _room.updateRoomPlan(beaconId: beaconId, currentPlan: currentPlan);

  Future<bool> participantSetNextMove({
    required String beaconId,
    required String targetUserId,
    required String nextMoveText,
    required int nextMoveSource,
    int? nextMoveStatus,
  }) =>
      _room.participantSetNextMove(
        beaconId: beaconId,
        targetUserId: targetUserId,
        nextMoveText: nextMoveText,
        nextMoveSource: nextMoveSource,
        nextMoveStatus: nextMoveStatus,
      );

  Future<List<BeaconFactCard>> fetchFactCards(String beaconId) =>
      _factCards.list(beaconId: beaconId);

  Future<void> pinFact({
    required String beaconId,
    required String factText,
    required int visibility,
    String? sourceMessageId,
  }) =>
      _factCards.pin(
        beaconId: beaconId,
        factText: factText,
        visibility: visibility,
        sourceMessageId: sourceMessageId,
      );

  Future<void> correctFact({
    required String beaconId,
    required String factCardId,
    required String newText,
  }) =>
      _factCards.correct(
        beaconId: beaconId,
        factCardId: factCardId,
        newText: newText,
      );

  Future<void> removeFact({
    required String beaconId,
    required String factCardId,
  }) =>
      _factCards.remove(beaconId: beaconId, factCardId: factCardId);

  Future<void> markRoomSeenIfAllowed(String beaconId) async {
    try {
      await _room.markRoomSeen(beaconId: beaconId);
    } on Object catch (_) {}
  }

  Future<void> markBlockerFromMessage({
    required String beaconId,
    required String messageId,
    required String title,
    String? affectedParticipantId,
    String? resolverParticipantId,
    int? visibility,
  }) =>
      _blockers
          .markBlocker(
            beaconId: beaconId,
            messageId: messageId,
            title: title,
            affectedParticipantId: affectedParticipantId,
            resolverParticipantId: resolverParticipantId,
            visibility: visibility,
          )
          .then((_) {});

  Future<void> needInfoFromMessage({
    required String beaconId,
    required String messageId,
    required String targetUserId,
    required String requestText,
  }) =>
      _blockers
          .needInfo(
            beaconId: beaconId,
            messageId: messageId,
            targetUserId: targetUserId,
            requestText: requestText,
          )
          .then((_) {});

  Future<void> markMessageDone({
    required String beaconId,
    required String messageId,
    required bool resolveBlocker,
  }) =>
      _blockers
          .markDone(
            beaconId: beaconId,
            messageId: messageId,
            resolveBlocker: resolveBlocker,
          )
          .then((_) {});
}
