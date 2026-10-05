import 'dart:convert';
import 'dart:typed_data';

import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_room_message_paint.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_read_watermark.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';

import '../../data/repository/beacon_fact_card_repository.dart';
import '../../data/repository/beacon_room_hints_repository.dart';
import '../../data/repository/beacon_threads_repository.dart';
import '../entity/beacon_room_invalidation.dart';
import '../entity/request_thread.dart';
import '../entity/room_seen_outcome.dart';
import '../entity/room_unread_snapshot.dart';
import '../room_read_watermark_store.dart';
import '../../../polling/data/repository/polling_repository.dart';

@singleton
base class BeaconThreadsCase extends UseCaseBase {
  BeaconThreadsCase(
    this._room,
    this._factCards,
    this._polling,
    this._hints,
    this._watermark,
    this._realtimeSyncCase, {
    required super.env,
    required super.logger,
  });

  final BeaconThreadsRepository _room;

  final BeaconFactCardRepository _factCards;

  final PollingRepository _polling;

  final BeaconRoomHintsRepository _hints;

  final RoomReadWatermarkStore _watermark;

  final RealtimeSyncCase _realtimeSyncCase;

  // roomSeenPeer is presence-only; omitted unlike roomSeen (unread convergence).
  static const _deskRelevantEntityTypes = {
    BeaconRoomEntityType.roomMessage,
    BeaconRoomEntityType.roomReaction,
    BeaconRoomEntityType.roomPoll,
    BeaconRoomEntityType.activityEvent,
    BeaconRoomEntityType.participant,
    BeaconRoomEntityType.factCard,
    BeaconRoomEntityType.coordinationItem,
    BeaconRoomEntityType.roomSeen,
  };

  Stream<String> get readWatermarkChanges => _watermark.changes;

  Stream<void> get catchUps => _realtimeSyncCase.catchUps.map((_) {});

  Stream<BeaconRoomInvalidation> get beaconRoomInvalidations =>
      _room.beaconRoomInvalidations;

  Stream<BeaconRoomInvalidation> get deskRelevantInvalidations =>
      beaconRoomInvalidations.where(
        (inv) => _deskRelevantEntityTypes.contains(inv.entityType),
      );

  /// Local room refresh for help-offer field edits (role label, etc.).
  void notifyHelpOfferRoomInvalidation(String beaconId) {
    _room.notifyLocalInvalidation(
      BeaconRoomInvalidation(
        beaconId: beaconId,
        entityType: BeaconRoomEntityType.helpOffer,
      ),
    );
  }

  Stream<String> get deskRelevantChanges =>
      deskRelevantInvalidations.map((inv) => inv.beaconId);

  Stream<RoomReadWatermarkKey> get threadReadWatermarkChanges =>
      _watermark.threadChanges;

  DateTime? readThrough(
    String beaconId, {
    String threadId = RequestThread.generalId,
  }) => _watermark.readThrough(beaconId, threadId: threadId);

  DateTime? syncedAt(
    String beaconId, {
    String threadId = RequestThread.generalId,
  }) => _watermark.syncedAt(beaconId, threadId: threadId);

  bool observeReadThrough(
    String beaconId,
    DateTime at, {
    String threadId = RequestThread.generalId,
  }) => _watermark.observeReadThrough(beaconId, at, threadId: threadId);

  void observeServerReadThrough(
    String beaconId,
    DateTime at, {
    String threadId = RequestThread.generalId,
  }) => _watermark.confirmSynced(beaconId, at, threadId: threadId);

  int resolveUnread({
    required String beaconId,
    required int serverCount,
    required DateTime? serverSeenAt,
    String threadId = RequestThread.generalId,
  }) => _watermark.resolveUnread(
    beaconId: beaconId,
    serverCount: serverCount,
    serverSeenAt: serverSeenAt,
    threadId: threadId,
  );

  Future<RoomUnreadSnapshot> fetchRoomUnreadSnapshot(String beaconId) async {
    try {
      final map = await _hints.fetchByBeaconIds([beaconId]);
      final hints = map[beaconId];
      return RoomUnreadSnapshot(
        count: hints?.roomUnreadCount ?? 0,
        serverSeenAt: hints?.lastSeenAt,
      );
    } on Object catch (_) {
      return const RoomUnreadSnapshot(count: 0);
    }
  }

  Stream<String> get beaconRoomRefresh => _room.beaconRoomRefresh;

  Future<List<RequestThread>> listThreads(String beaconId) =>
      _room.fetchThreads(beaconId);

  // DORMANT(item-threads): threadItemId filters item-thread messages; always null in production.
  // Rooms are General-only (guard: beacon_room_message_general_only_guard, DiscussionScopeDisabledException); thread_item_id is always NULL for new rows. Do not design for this path. See #192.
  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
    String? threadItemId,
  }) => _room.fetchMessages(
    beaconId: beaconId,
    beforeIso: beforeIso,
    threadItemId: threadItemId,
  );

  /// Returns the exact target only when the server authorizes this viewer.
  Future<RoomMessage?> fetchMessageTarget({
    required String beaconId,
    required String messageId,
  }) => _room.fetchMessageTarget(beaconId: beaconId, messageId: messageId);

  Future<List<BeaconParticipant>> fetchParticipants(String beaconId) =>
      _room.fetchParticipants(beaconId);

  Future<List<RoomReadWatermark>> fetchMainRoomReadWatermarks(String beaconId) =>
      _room.fetchMainRoomReadWatermarks(beaconId);

  // DORMANT(item-threads): threadItemId targets item-thread scope; always null in production.
  // Rooms are General-only (guard: beacon_room_message_general_only_guard, DiscussionScopeDisabledException); thread_item_id is always NULL for new rows. Do not design for this path. See #192.
  Future<String?> createMessage({
    required String beaconId,
    required String body,
    String? replyToMessageId,
    String? threadItemId,
    List<RoomPendingUpload> uploads = const [],
    List<String> explicitMentionUserIds = const [],
    List<int> explicitMentionOffsets = const [],
    List<int> explicitMentionLengths = const [],
    String? quotedFactCardId,
    int? quotedFactRevisionSeq,
  }) async {
    if (body.trim().isEmpty && uploads.isEmpty && quotedFactCardId == null) {
      return null;
    }
    final first = uploads.isNotEmpty ? uploads.first : null;
    final extras = uploads.length > 1
        ? uploads.sublist(1)
        : const <RoomPendingUpload>[];
    final messageId = await _room.createMessage(
      beaconId: beaconId,
      body: body,
      replyToMessageId: replyToMessageId,
      threadItemId: threadItemId,
      firstAttachment: first,
      explicitMentionUserIds: explicitMentionUserIds,
      explicitMentionOffsets: explicitMentionOffsets,
      explicitMentionLengths: explicitMentionLengths,
      quotedFactCardId: quotedFactCardId,
      quotedFactRevisionSeq: quotedFactRevisionSeq,
    );
    for (final u in extras) {
      await _room.addMessageAttachment(
        beaconId: beaconId,
        messageId: messageId,
        upload: u,
      );
    }
    return messageId;
  }

  RoomMessage roomMessageFromPaint({
    required RealtimeRoomMessagePaint paint,
    required List<RoomMessage> currentMessages,
    required List<BeaconParticipant> participants,
  }) {
    var author = const Profile();
    for (final message in currentMessages) {
      if (message.authorId == paint.authorId) {
        author = message.author;
        break;
      }
    }
    if (author.id.isEmpty) {
      for (final participant in participants) {
        if (participant.userId == paint.authorId) {
          author = Profile(
            id: paint.authorId,
            displayName: participant.userTitle,
            handle: participant.handle,
            image:
                participant.userHasPicture && participant.userImageId.isNotEmpty
                ? ImageEntity(
                    id: participant.userImageId,
                    authorId: paint.authorId,
                    blurHash: participant.userBlurHash,
                    height: participant.userPicHeight,
                    width: participant.userPicWidth,
                  )
                : null,
          );
          break;
        }
      }
    }
    if (author.id.isEmpty) {
      author = Profile(id: paint.authorId);
    }
    return RoomMessage(
      id: paint.id,
      beaconId: paint.beaconId,
      authorId: paint.authorId,
      body: paint.body,
      createdAt: paint.createdAt,
      editedAt: paint.editedAt,
      author: author,
      mentions: paint.mentions,
      mentionSpans: paint.mentionSpans,
      threadItemId: paint.threadItemId,
      replyToMessageId: paint.replyToMessageId,
      replyToAuthorId: paint.replyToAuthorId,
      replyToAuthorTitle: paint.replyToAuthorTitle,
      replyToBodyExcerpt: paint.replyToBodyExcerpt,
      replyToHasAttachments: paint.replyToHasAttachments,
      semanticMarker: paint.semanticMarker,
      systemPayloadJson: paint.systemPayload == null
          ? null
          : jsonEncode(paint.systemPayload),
      quotedFact: paint.quotedFact,
    );
  }

  Future<void> editMessage({
    required String beaconId,
    required String messageId,
    required String body,
  }) => _room.editMessage(
    beaconId: beaconId,
    messageId: messageId,
    body: body,
  );

  Future<void> deleteMessage({
    required String beaconId,
    required String messageId,
  }) => _room.deleteMessage(
    beaconId: beaconId,
    messageId: messageId,
  );

  Future<Uint8List> downloadRoomAttachment(String attachmentId) =>
      _room.downloadRoomAttachmentBytes(attachmentId);

  Future<bool> participantOfferHelp({
    required String beaconId,
    required String note,
  }) => _room.participantOfferHelp(beaconId: beaconId, note: note);

  Future<bool> admit({
    required String beaconId,
    required String participantUserId,
  }) => _room.admit(beaconId: beaconId, participantUserId: participantUserId);

  Future<bool> promoteSteward({
    required String beaconId,
    required String stewardUserId,
  }) => _room.promoteSteward(beaconId: beaconId, stewardUserId: stewardUserId);

  Future<bool> toggleReaction({
    required String beaconId,
    required String messageId,
    required String emoji,
  }) => _room.toggleReaction(
    beaconId: beaconId,
    messageId: messageId,
    emoji: emoji,
  );

  Future<BeaconRoomState> fetchBeaconRoomState(String beaconId) =>
      _room.fetchBeaconRoomState(beaconId);

  Future<CoordinationItem?> fetchOpenCoordinationBlocker(String beaconId) async =>
      null;

  /// Legacy item reply counts are no longer loaded; returns an empty list.
  Future<List<CoordinationItem>> fetchCoordinationItems(String beaconId) async =>
      const [];

  Future<void> updateRoomNowLine({
    required String beaconId,
    required String currentLine,
  }) => _room.updateRoomNowLine(
    beaconId: beaconId,
    text: currentLine,
  );

  Future<CoordinationItem?> fetchCurrentCoordinationPlan(String beaconId) async =>
      null;

  Future<List<BeaconFactCard>> fetchFactCards(String beaconId) =>
      _factCards.list(beaconId: beaconId);

  Future<void> pinFact({
    required String beaconId,
    required String factText,
    required int visibility,
    String? sourceMessageId,
  }) => _factCards.pin(
    beaconId: beaconId,
    factText: factText,
    visibility: visibility,
    sourceMessageId: sourceMessageId,
  );

  Future<void> correctFact({
    required String beaconId,
    required String factCardId,
    required String newText,
    required int baseRevisionSeq,
    String? attachmentsJson,
  }) => _factCards.correct(
    beaconId: beaconId,
    factCardId: factCardId,
    newText: newText,
    baseRevisionSeq: baseRevisionSeq,
    attachmentsJson: attachmentsJson,
  );

  Future<void> removeFact({
    required String beaconId,
    required String factCardId,
  }) => _factCards.remove(beaconId: beaconId, factCardId: factCardId);

  Future<void> setFactVisibility({
    required String beaconId,
    required String factCardId,
    required int visibility,
  }) => _factCards.setVisibility(
    beaconId: beaconId,
    factCardId: factCardId,
    visibility: visibility,
  );

  // DORMANT(item-threads): non-null threadItemId marks item-thread seen watermarks.
  // Rooms are General-only (guard: beacon_room_message_general_only_guard, DiscussionScopeDisabledException); thread_item_id is always NULL for new rows. Do not design for this path. See #192.
  Future<RoomSeenOutcome> markRoomSeenIfAllowed({
    required String beaconId,
    required DateTime readThroughAt,
    String? threadItemId,
  }) async {
    final threadId = threadItemId ?? RequestThread.generalId;
    try {
      final persistedAt = await _room.markThreadSeen(
        beaconId: beaconId,
        threadId: threadId,
        readThroughAt: readThroughAt,
      );
      _watermark.confirmSynced(beaconId, persistedAt, threadId: threadId);
      return RoomSeenSucceeded(persistedAt);
    } on Object catch (e) {
      return RoomSeenFailed(e);
    }
  }

  Future<bool> markMessageSemanticDone({
    required String beaconId,
    required String messageId,
  }) => _room.markMessageSemanticDone(beaconId: beaconId, messageId: messageId);

  Future<void> votePoll({
    required String pollingId,
    required List<String> variantIds,
    int? score,
  }) =>
      _polling.vote(pollingId: pollingId, variantIds: variantIds, score: score);

  Future<RoomBatonData?> batonCreate({
    required String messageId,
    required List<({String userId, int tier})> candidates,
  }) => _room.batonCreate(messageId: messageId, candidates: candidates);

  Future<RoomBatonData?> batonRespond({
    required String batonId,
    required bool canHelp,
  }) => _room.batonRespond(batonId: batonId, canHelp: canHelp);

  Future<RoomBatonData?> batonSelect({
    required String batonId,
    String? userId,
  }) => _room.batonSelect(batonId: batonId, userId: userId);

  Future<bool> batonCancel({required String batonId}) =>
      _room.batonCancel(batonId: batonId);

  Future<void> createPoll({
    required String beaconId,
    required String question,
    required List<String> variants,
    String pollType = 'single',
    bool isAnonymous = true,
    bool allowRevote = true,
  }) => _room.createPoll(
    beaconId: beaconId,
    question: question,
    variants: variants,
    pollType: pollType,
    isAnonymous: isAnonymous,
    allowRevote: allowRevote,
  );
}
