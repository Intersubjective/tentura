import 'dart:typed_data';

import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../../data/repository/beacon_blocker_repository.dart';
import '../../data/repository/beacon_fact_card_repository.dart';
import '../../data/repository/beacon_room_hints_repository.dart';
import '../../data/repository/beacon_room_repository.dart';
import '../../../coordination_item/domain/use_case/coordination_item_case.dart';
import '../../../polling/data/repository/polling_repository.dart';

@singleton
final class BeaconRoomCase extends UseCaseBase {
  BeaconRoomCase(
    this._room,
    this._factCards,
    this._blockers,
    this._polling,
    this._hints,
    this._coordinationItemCase, {
    required super.env,
    required super.logger,
  });

  final BeaconRoomRepository _room;

  final BeaconFactCardRepository _factCards;

  final BeaconBlockerRepository _blockers;

  final PollingRepository _polling;

  final BeaconRoomHintsRepository _hints;

  final CoordinationItemCase _coordinationItemCase;

  Stream<String> get beaconRoomRefresh => _room.beaconRoomRefresh;

  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
    String? threadItemId,
  }) =>
      _room.fetchMessages(
        beaconId: beaconId,
        beforeIso: beforeIso,
        threadItemId: threadItemId,
      );

  Future<List<BeaconParticipant>> fetchParticipants(String beaconId) =>
      _room.fetchParticipants(beaconId);

  Future<void> createMessage({
    required String beaconId,
    required String body,
    String? replyToMessageId,
    String? threadItemId,
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
      threadItemId: threadItemId,
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

  Future<void> editMessage({
    required String beaconId,
    required String messageId,
    required String body,
  }) =>
      _room.editMessage(
        beaconId: beaconId,
        messageId: messageId,
        body: body,
      );

  Future<void> deleteMessage({
    required String beaconId,
    required String messageId,
  }) =>
      _room.deleteMessage(
        beaconId: beaconId,
        messageId: messageId,
      );

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

  Future<CoordinationItem?> fetchOpenCoordinationBlocker(
    String beaconId,
  ) async {
    final items = await _coordinationItemCase.listByBeacon(
      beaconId,
      status: CoordinationItemStatus.open.value,
      kind: CoordinationItemKind.blocker.value,
    );
    return items.firstOrNull;
  }

  Future<void> updateRoomPlan({
    required String beaconId,
    required String currentPlan,
    String body = '',
    String? targetPersonId,
    String? linkedMessageId,
  }) =>
      _coordinationItemCase
          .updatePlan(
            beaconId: beaconId,
            title: currentPlan,
            body: body,
            targetPersonId: targetPersonId,
            linkedMessageId: linkedMessageId,
          )
          .then((_) {});

  Future<CoordinationItem?> fetchCurrentCoordinationPlan(String beaconId) =>
      _coordinationItemCase.fetchCurrentRootPlan(beaconId);

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

  Future<void> setFactVisibility({
    required String beaconId,
    required String factCardId,
    required int visibility,
  }) =>
      _factCards.setVisibility(
        beaconId: beaconId,
        factCardId: factCardId,
        visibility: visibility,
      );

  Future<void> markRoomSeenIfAllowed({
    required String beaconId,
    String? threadItemId,
  }) async {
    try {
      await _room.markRoomSeen(
        beaconId: beaconId,
        threadItemId: threadItemId,
      );
      _hints.notifyRoomSeen(beaconId);
    } on Object catch (_) {}
  }

  Future<void> markBlockerFromMessage({
    required String beaconId,
    required String messageId,
    required String title,
    String body = '',
    String? targetPersonId,
  }) =>
      _coordinationItemCase
          .markBlocker(
            beaconId: beaconId,
            title: title,
            body: body,
            targetPersonId: targetPersonId,
            linkedMessageId: messageId,
          )
          .then((_) {});

  Future<void> markAskFromMessage({
    required String beaconId,
    required String messageId,
    required String title,
    required String targetPersonId,
    String body = '',
  }) =>
      _coordinationItemCase
          .markAsk(
            beaconId: beaconId,
            title: title,
            targetPersonId: targetPersonId,
            body: body,
            linkedMessageId: messageId,
          )
          .then((_) {});

  Future<void> createPromise({
    required String beaconId,
    required String title,
    required String targetPersonId,
    String body = '',
    String? linkedMessageId,
  }) =>
      _coordinationItemCase
          .createPromise(
            beaconId: beaconId,
            title: title,
            targetPersonId: targetPersonId,
            body: body,
            linkedMessageId: linkedMessageId,
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

  Future<void> votePoll({
    required String pollingId,
    required List<String> variantIds,
    int? score,
  }) =>
      _polling.vote(pollingId: pollingId, variantIds: variantIds, score: score);

  Future<void> createPoll({
    required String beaconId,
    required String question,
    required List<String> variants,
    String pollType = 'single',
    bool isAnonymous = true,
    bool allowRevote = true,
  }) =>
      _room.createPoll(
        beaconId: beaconId,
        question: question,
        variants: variants,
        pollType: pollType,
        isAnonymous: isAnonymous,
        allowRevote: allowRevote,
      );
}
