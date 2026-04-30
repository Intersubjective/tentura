import 'dart:async';
import 'dart:typed_data';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/service/beacon_room_push_service.dart';
import 'package:tentura_server/data/storage/remote_storage.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/exception.dart';

import 'package:tentura_root/utils/infer_image_mime_from_bytes.dart';

import 'package:tentura_server/utils/id.dart';
import 'package:tentura_server/utils/read_uint8_stream_with_limit.dart';
import 'package:tentura_server/utils/sanitized_attachment_name.dart';

import '_use_case_base.dart';

/// Room coordination: admission, steward, messages (server-side rules).
// TODO(contract): tighten permissions with visibility / forward graph —
// current checks are author-or-steward or admitted-member only.
@Singleton(order: 2)
final class BeaconRoomCase extends UseCaseBase {
  BeaconRoomCase(
    this._room,
    this._factCards,
    this._push,
    this._imageRepository,
    this._tasksRepository,
    this._remoteStorage, {
    required super.env,
    required super.logger,
  });

  final BeaconRoomRepository _room;

  final BeaconFactCardRepository _factCards;

  final BeaconRoomPushService _push;

  final ImageRepositoryPort _imageRepository;

  final TaskRepositoryPort _tasksRepository;

  final RemoteStorage _remoteStorage;

  Future<bool> _canUseRoom({
    required String beaconId,
    required String userId,
  }) async {
    if (await _room.isBeaconAuthor(beaconId: beaconId, userId: userId)) {
      return true;
    }
    if (await _room.isBeaconSteward(beaconId: beaconId, userId: userId)) {
      return true;
    }
    final p =
        await _room.findParticipant(beaconId: beaconId, userId: userId);
    return p?.roomAccess == RoomAccessBits.admitted;
  }

  Future<Map<String, Object?>> createMessage({
    required String beaconId,
    required String userId,
    required String body,
    String? replyToMessageId,
    Stream<Uint8List>? attachmentBytes,
    String? attachmentFilename,
    String? attachmentMimeType,
  }) async {
    final allowed = await _canUseRoom(beaconId: beaconId, userId: userId);
    if (!allowed) {
      throw const UnauthorizedException(
        description: 'Room access required',
      );
    }
    final trimmed = body.trim();
    Uint8List? payload;
    if (attachmentBytes != null) {
      payload = await readUint8StreamWithLimit(
        attachmentBytes,
        kMaxRoomMessageAttachmentBytes,
      );
      if (payload.isEmpty) {
        payload = null;
      }
    }
    if (trimmed.isEmpty && payload == null) {
      throw const BeaconCreateException(
        description: 'Message text or attachment required',
      );
    }
    final row = await _room.insertRoomMessage(
      beaconId: beaconId,
      authorId: userId,
      body: trimmed,
      replyToMessageId: replyToMessageId,
    );
    if (payload != null) {
      await _addAttachmentBytesToMessage(
        beaconId: beaconId,
        userId: userId,
        messageId: row.id,
        mutatingUserId: userId,
        bytes: payload,
        uploadFilename: attachmentFilename,
        uploadMimeType: attachmentMimeType,
      );
    }
    return {'id': row.id, 'beaconId': row.beaconId};
  }

  Future<List<Map<String, Object?>>> listMessages({
    required String beaconId,
    required String userId,
    String? beforeIso,
  }) async {
    final allowed = await _canUseRoom(beaconId: beaconId, userId: userId);
    if (!allowed) {
      throw const UnauthorizedException(
        description: 'Room access required',
      );
    }
    final before =
        beforeIso != null ? DateTime.tryParse(beforeIso) : null;
    return _room.listMessagesEnriched(
      beaconId: beaconId,
      viewerUserId: userId,
      before: before,
    );
  }

  Future<Map<String, Object?>> beaconRoomStateGet({
    required String beaconId,
    required String userId,
  }) async {
    final allowed = await _canUseRoom(beaconId: beaconId, userId: userId);
    if (!allowed) {
      throw const UnauthorizedException(
        description: 'Room access required',
      );
    }
    final row = await _room.getBeaconRoomState(beaconId);
    final nowIso = DateTime.timestamp().toUtc().toIso8601String();
    if (row == null) {
      return {
        'beaconId': beaconId,
        'currentPlan': '',
        'openBlockerId': null,
        'openBlockerTitle': null,
        'lastRoomMeaningfulChange': null,
        'updatedAt': nowIso,
        'updatedBy': null,
      };
    }
    final blockerTitle = row.openBlockerId == null
        ? null
        : await _room.getBlockerTitle(row.openBlockerId!);
    return {
      'beaconId': row.beaconId,
      'currentPlan': row.currentPlan,
      'openBlockerId': row.openBlockerId,
      'openBlockerTitle': blockerTitle,
      'lastRoomMeaningfulChange': row.lastRoomMeaningfulChange,
      'updatedAt': row.updatedAt.dateTime.toIso8601String(),
      'updatedBy': row.updatedBy,
    };
  }

  /// Inbox / My Work: batch room visibility, unread counts, public fact snippet.
  Future<List<Map<String, Object?>>> inboxRoomContextBatch({
    required String userId,
    required List<String> beaconIds,
  }) async {
    final unique = beaconIds.toSet().toList();
    if (unique.isEmpty) {
      return [];
    }
    final slice = unique.length > 80 ? unique.sublist(0, 80) : unique;
    final out = <Map<String, Object?>>[];
    for (final bid in slice) {
      final allowed = await _canUseRoom(beaconId: bid, userId: userId);
      final factSnippet = await _factCards.latestPublicFactSnippet(bid);
      if (!allowed) {
        out.add({
          'beaconId': bid,
          'isRoomMember': false,
          'currentPlan': null,
          'lastRoomMeaningfulChange': null,
          'nextMoveText': null,
          'roomUnreadCount': 0,
          'openBlockerTitle': null,
          'publicFactSnippet': factSnippet,
        });
        continue;
      }
      final p = await _room.findParticipant(beaconId: bid, userId: userId);
      final st = await _room.getBeaconRoomState(bid);
      final seenAt = p?.lastSeenRoomAt?.dateTime;
      final unread = p == null
          ? 0
          : await _room.countRoomMessagesAfter(
              beaconId: bid,
              after: seenAt,
            );
      final blockerTitle = st?.openBlockerId == null
          ? null
          : await _room.getBlockerTitle(st!.openBlockerId!);
      out.add({
        'beaconId': bid,
        'isRoomMember': true,
        'currentPlan': st?.currentPlan,
        'lastRoomMeaningfulChange': st?.lastRoomMeaningfulChange,
        'nextMoveText': p?.nextMoveText,
        'roomUnreadCount': unread,
        'openBlockerTitle': blockerTitle,
        'publicFactSnippet': factSnippet,
      });
    }
    return out;
  }

  Future<bool> beaconRoomStatePlanUpdate({
    required String beaconId,
    required String userId,
    required String currentPlan,
  }) async {
    final allowed = await _canUseRoom(beaconId: beaconId, userId: userId);
    if (!allowed) {
      throw const UnauthorizedException(
        description: 'Room access required',
      );
    }
    final plan = currentPlan.trim();
    await _room.upsertBeaconRoomPlan(
      beaconId: beaconId,
      currentPlan: plan,
      updatedByUserId: userId,
    );
    final msg = await _room.insertRoomMessage(
      beaconId: beaconId,
      authorId: userId,
      body: '',
      semanticMarker: BeaconRoomSemanticMarker.updatePlan,
      systemPayload: {'currentPlan': plan},
    );
    await _room.insertActivityEvent(
      beaconId: beaconId,
      visibility: BeaconActivityEventVisibilityBits.room,
      type: BeaconActivityEventTypeBits.planUpdated,
      actorId: userId,
      sourceMessageId: msg.id,
      diff: <String, Object?>{'currentPlan': plan},
    );
    final admitted = await _room.listAdmittedUserIds(beaconId);
    unawaited(
      _push.notifyPlanUpdatedToRoom(
        beaconId: beaconId,
        actorUserId: userId,
        admittedUserIds: admitted,
      ),
    );
    return true;
  }

  Future<List<Map<String, Object?>>> listActivityEvents({
    required String beaconId,
    required String userId,
  }) async {
    final allowed = await _canUseRoom(beaconId: beaconId, userId: userId);
    if (!allowed) {
      throw const UnauthorizedException(
        description: 'Room access required',
      );
    }
    return _room.listActivityEvents(beaconId: beaconId);
  }

  /// Message → Mark blocker (Phase 5).
  Future<bool> beaconRoomMessageMarkBlocker({
    required String beaconId,
    required String userId,
    required String messageId,
    required String title,
    String? affectedParticipantId,
    String? resolverParticipantId,
    int? visibility,
  }) async {
    final allowed = await _canUseRoom(beaconId: beaconId, userId: userId);
    if (!allowed) {
      throw const UnauthorizedException(
        description: 'Room access required',
      );
    }
    final vis = visibility ?? BeaconFactCardVisibilityBits.room;
    if (vis == BeaconFactCardVisibilityBits.public) {
      final author =
          await _room.isBeaconAuthor(beaconId: beaconId, userId: userId);
      final steward =
          await _room.isBeaconSteward(beaconId: beaconId, userId: userId);
      if (!author && !steward) {
        throw const UnauthorizedException(
          description: 'Author or steward only for public blocker',
        );
      }
    }
    final msg = await _room.getRoomMessageById(messageId);
    if (msg == null || msg.beaconId != beaconId) {
      throw IdNotFoundException(
        id: messageId,
        description: 'Room message not on this beacon',
      );
    }
    final blockerId = await _room.insertBlockerOpen(
      beaconId: beaconId,
      title: title,
      visibility: vis,
      openedBy: userId,
      openedFromMessageId: messageId,
      affectedParticipantId: affectedParticipantId,
      resolverParticipantId: resolverParticipantId,
    );
    await _room.insertActivityEvent(
      beaconId: beaconId,
      visibility: vis == BeaconFactCardVisibilityBits.public
          ? BeaconActivityEventVisibilityBits.public
          : BeaconActivityEventVisibilityBits.room,
      type: BeaconActivityEventTypeBits.blockerOpened,
      actorId: userId,
      sourceMessageId: messageId,
      diff: <String, Object?>{
        'blockerId': blockerId,
        'title': title.trim(),
      },
    );
    final notifyIds = await _room.blockerOpenedNotifyUserIds(
      beaconId: beaconId,
      openedByUserId: userId,
      affectedParticipantId: affectedParticipantId,
      resolverParticipantId: resolverParticipantId,
    );
    unawaited(
      _push.notifyBlockerRoomEvent(
        beaconId: beaconId,
        actorUserId: userId,
        receiverIds: notifyIds,
        body: 'Blocker opened: ${title.trim()}',
      ),
    );
    return true;
  }

  /// Message → Need info (Phase 5).
  Future<bool> beaconRoomMessageNeedInfo({
    required String beaconId,
    required String userId,
    required String messageId,
    required String targetUserId,
    required String requestText,
  }) async {
    final allowed = await _canUseRoom(beaconId: beaconId, userId: userId);
    if (!allowed) {
      throw const UnauthorizedException(
        description: 'Room access required',
      );
    }
    final msg = await _room.getRoomMessageById(messageId);
    if (msg == null || msg.beaconId != beaconId) {
      throw IdNotFoundException(
        id: messageId,
        description: 'Room message not on this beacon',
      );
    }
    final target = await _room.findParticipant(
      beaconId: beaconId,
      userId: targetUserId,
    );
    if (target == null) {
      throw IdNotFoundException(
        id: targetUserId,
        description: 'Participant not found for beacon',
      );
    }
    await _room.setParticipantNeedsInfo(
      participantRowId: target.id,
      actingUserId: userId,
      requestText: requestText,
      linkedMessageId: messageId,
    );
    await _room.insertRoomMessage(
      beaconId: beaconId,
      authorId: userId,
      body: '',
      semanticMarker: BeaconRoomSemanticMarker.needInfo,
      systemPayload: <String, Object?>{
        'targetUserId': targetUserId,
        'requestText': requestText.trim(),
        'sourceMessageId': messageId,
      },
    );
    await _room.insertActivityEvent(
      beaconId: beaconId,
      visibility: BeaconActivityEventVisibilityBits.room,
      type: BeaconActivityEventTypeBits.needInfoOpened,
      actorId: userId,
      targetUserId: targetUserId,
      sourceMessageId: messageId,
      diff: <String, Object?>{'requestText': requestText.trim()},
    );
    if (targetUserId != userId) {
      unawaited(
        _push.notifyNeedInfoRequested(
          receiverId: targetUserId,
          beaconId: beaconId,
          actorUserId: userId,
        ),
      );
    }
    return true;
  }

  /// Mark done — resolve linked blocker or mark message semantic "done" (Phase 5).
  Future<bool> roomMessageMarkDone({
    required String beaconId,
    required String userId,
    required String messageId,
    required bool resolveBlocker,
  }) async {
    final allowed = await _canUseRoom(beaconId: beaconId, userId: userId);
    if (!allowed) {
      throw const UnauthorizedException(
        description: 'Room access required',
      );
    }
    final msg = await _room.getRoomMessageById(messageId);
    if (msg == null || msg.beaconId != beaconId) {
      throw IdNotFoundException(
        id: messageId,
        description: 'Room message not on this beacon',
      );
    }
    if (resolveBlocker) {
      final bid = msg.linkedBlockerId;
      if (bid == null || bid.isEmpty) {
        throw const UnspecifiedException(
          description: 'Message has no linked blocker to resolve',
        );
      }
      await _room.resolveBlocker(
        blockerId: bid,
        resolvedByUserId: userId,
        resolvedFromMessageId: messageId,
      );
      await _room.insertActivityEvent(
        beaconId: beaconId,
        visibility: BeaconActivityEventVisibilityBits.room,
        type: BeaconActivityEventTypeBits.blockerResolved,
        actorId: userId,
        sourceMessageId: messageId,
        diff: <String, Object?>{'blockerId': bid},
      );
      final notifyIds =
          await _room.blockerResolvedNotifyUserIds(
        blockerId: bid,
        resolvedByUserId: userId,
      );
      unawaited(
        _push.notifyBlockerRoomEvent(
          beaconId: beaconId,
          actorUserId: userId,
          receiverIds: notifyIds,
          body: 'A blocker was resolved',
        ),
      );
    } else {
      await _room.markRoomMessageSemanticDone(
        messageId: messageId,
        actingUserId: userId,
      );
      await _room.insertActivityEvent(
        beaconId: beaconId,
        visibility: BeaconActivityEventVisibilityBits.room,
        type: BeaconActivityEventTypeBits.doneMarked,
        actorId: userId,
        sourceMessageId: messageId,
        diff: const <String, Object?>{'kind': 'message'},
      );
    }
    return true;
  }

  Future<bool> beaconParticipantRoomSeen({
    required String beaconId,
    required String userId,
  }) async {
    final allowed = await _canUseRoom(beaconId: beaconId, userId: userId);
    if (!allowed) {
      throw const UnauthorizedException(
        description: 'Room access required',
      );
    }
    await _room.markParticipantRoomSeen(
      beaconId: beaconId,
      userId: userId,
    );
    return true;
  }

  /// Room members (same visibility envelope as chat): author, steward, or
  /// admitted participants.
  Future<List<Map<String, Object?>>> listParticipants({
    required String beaconId,
    required String userId,
  }) async {
    final allowed = await _canUseRoom(beaconId: beaconId, userId: userId);
    if (!allowed) {
      throw const UnauthorizedException(
        description: 'Room access required',
      );
    }
    final rows = await _room.listParticipants(beaconId);
    return rows
        .map(
          (r) => <String, Object?>{
            'id': r.id,
            'beaconId': r.beaconId,
            'userId': r.userId,
            'role': r.role,
            'status': r.status,
            'roomAccess': r.roomAccess,
            'offerNote': r.offerNote,
            'nextMoveText': r.nextMoveText,
            'nextMoveStatus': r.nextMoveStatus,
            'nextMoveSource': r.nextMoveSource,
            'linkedMessageId': r.linkedMessageId,
            'createdAt': r.createdAt.dateTime.toIso8601String(),
            'updatedAt': r.updatedAt.dateTime.toIso8601String(),
          },
        )
        .toList();
  }

  Future<void> offerHelp({
    required String beaconId,
    required String userId,
    required String note,
  }) async {
    await _room.participantOfferHelp(
      beaconId: beaconId,
      userId: userId,
      note: note.trim(),
    );
    final author = await _room.beaconAuthorUserId(beaconId);
    final stewards = await _room.listStewardUserIds(beaconId);
    final moderators = <String>{
      if (author != null && author.isNotEmpty) author,
      ...stewards,
    }.toList();
    unawaited(
      _push.notifyHelpOfferedToModerators(
        beaconId: beaconId,
        offererUserId: userId,
        moderatorUserIds: moderators,
      ),
    );
  }

  Future<void> admit({
    required String beaconId,
    required String participantUserId,
    required String actorUserId,
  }) async {
    final author =
        await _room.isBeaconAuthor(beaconId: beaconId, userId: actorUserId);
    final steward = await _room.isBeaconSteward(
      beaconId: beaconId,
      userId: actorUserId,
    );
    if (!author && !steward) {
      throw const UnauthorizedException(description: 'Author or steward only');
    }
    await _room.admitParticipant(
      beaconId: beaconId,
      participantUserId: participantUserId,
      actorUserId: actorUserId,
    );
    unawaited(
      _push.notifyRoomAdmitted(
        receiverId: participantUserId,
        beaconId: beaconId,
      ),
    );
  }

  Future<void> stewardPromote({
    required String beaconId,
    required String stewardUserId,
    required String authorUserId,
  }) async {
    final author =
        await _room.isBeaconAuthor(beaconId: beaconId, userId: authorUserId);
    if (!author) {
      throw const UnauthorizedException(description: 'Author only');
    }
    await _room.setBeaconSteward(
      beaconId: beaconId,
      stewardUserId: stewardUserId,
      authorUserId: authorUserId,
    );
  }

  Future<void> reactionToggle({
    required String beaconId,
    required String messageId,
    required String userId,
    required String emoji,
  }) async {
    final allowed = await _canUseRoom(beaconId: beaconId, userId: userId);
    if (!allowed) {
      throw const UnauthorizedException(
        description: 'Room access required',
      );
    }
    await _room.toggleReaction(
      messageId: messageId,
      userId: userId,
      emoji: emoji,
    );
  }

  /// Sets expected next move for [targetUserId]'s participant row (author/steward
  /// for others; admitted members for self).
  Future<bool> participantSetNextMove({
    required String beaconId,
    required String actorUserId,
    required String targetUserId,
    required String nextMoveText,
    required int nextMoveSource,
    int? nextMoveStatus,
  }) async {
    final trimmed = nextMoveText.trim();
    if (trimmed.isEmpty) {
      throw const UnspecifiedException(description: 'nextMoveText is empty');
    }

    final author =
        await _room.isBeaconAuthor(beaconId: beaconId, userId: actorUserId);
    final steward =
        await _room.isBeaconSteward(beaconId: beaconId, userId: actorUserId);
    final self = actorUserId == targetUserId;

    if (!self) {
      if (!author && !steward) {
        throw const UnauthorizedException(
          description: 'Author or steward only when setting for others',
        );
      }
    } else {
      if (!author && !steward) {
        final allowed = await _canUseRoom(
          beaconId: beaconId,
          userId: actorUserId,
        );
        if (!allowed) {
          throw const UnauthorizedException(
            description: 'Room access required',
          );
        }
      }
    }

    final target = await _room.findParticipant(
      beaconId: beaconId,
      userId: targetUserId,
    );
    if (target == null) {
      throw IdNotFoundException(
        id: targetUserId,
        description: 'Participant not on beacon',
      );
    }

    await _room.updateParticipantNextMoveFields(
      actorUserId: actorUserId,
      participantRowId: target.id,
      nextMoveText: trimmed,
      nextMoveSource: nextMoveSource,
      nextMoveStatus: nextMoveStatus,
    );

    await _room.insertRoomMessage(
      beaconId: beaconId,
      authorId: actorUserId,
      body: '',
      linkedParticipantId: target.id,
      semanticMarker: BeaconRoomSemanticMarker.participantStatusChanged,
      systemPayload: <String, Object?>{
        'targetUserId': targetUserId,
        'nextMoveText': trimmed,
        'nextMoveSource': nextMoveSource,
        ...?(nextMoveStatus == null
            ? null
            : <String, Object?>{'nextMoveStatus': nextMoveStatus}),
      },
    );
    unawaited(
      _push.notifyNextMoveUpdated(
        beaconId: beaconId,
        targetUserId: targetUserId,
        actorUserId: actorUserId,
      ),
    );
    return true;
  }

  Future<bool> addMessageAttachment({
    required String beaconId,
    required String userId,
    required String messageId,
    required Stream<Uint8List> attachmentBytes,
    String? attachmentFilename,
    String? attachmentMimeType,
  }) async {
    final allowed = await _canUseRoom(beaconId: beaconId, userId: userId);
    if (!allowed) {
      throw const UnauthorizedException(description: 'Room access required');
    }
    final msg = await _room.getRoomMessageById(messageId);
    if (msg == null || msg.beaconId != beaconId) {
      throw IdNotFoundException(
        id: messageId,
        description: 'Room message not found',
      );
    }
    if (msg.authorId != userId) {
      throw const UnauthorizedException(
        description: 'Only the message author can add attachments',
      );
    }
    final payload = await readUint8StreamWithLimit(
      attachmentBytes,
      kMaxRoomMessageAttachmentBytes,
    );
    if (payload.isEmpty) {
      throw const BeaconCreateException(description: 'Empty attachment');
    }
    await _addAttachmentBytesToMessage(
      beaconId: beaconId,
      userId: userId,
      messageId: messageId,
      mutatingUserId: userId,
      bytes: payload,
      uploadFilename: attachmentFilename,
      uploadMimeType: attachmentMimeType,
    );
    return true;
  }

  Future<({Uint8List bytes, String mime, String fileName})> downloadAttachment({
    required String userId,
    required String attachmentId,
  }) async {
    final row = await _room.getRoomMessageAttachmentById(attachmentId);
    if (row == null) {
      throw IdNotFoundException(
        id: attachmentId,
        description: 'Attachment not found',
      );
    }
    if (row.kind != BeaconRoomMessageAttachmentKind.file ||
        row.fileUrl == null ||
        row.fileUrl!.isEmpty) {
      throw const IdWrongException(
        description: 'Not a downloadable file attachment',
      );
    }
    final msg = await _room.getRoomMessageById(row.messageId);
    if (msg == null) {
      throw IdNotFoundException(
        id: attachmentId,
        description: 'Message missing',
      );
    }
    final roomOk = await _canUseRoom(beaconId: msg.beaconId, userId: userId);
    if (!roomOk) {
      throw const UnauthorizedException(description: 'Room access required');
    }
    final bytes = await _remoteStorage.getObject(row.fileUrl!);
    final name =
        row.fileName.trim().isEmpty ? 'download' : row.fileName.trim();
    return (bytes: bytes, mime: row.mime, fileName: name);
  }

  Future<void> _addAttachmentBytesToMessage({
    required String beaconId,
    required String userId,
    required String messageId,
    required String mutatingUserId,
    required Uint8List bytes,
    String? uploadFilename,
    String? uploadMimeType,
  }) async {
    final count = await _room.countAttachmentsForMessage(messageId);
    if (count >= kMaxRoomMessageAttachments) {
      throw const BeaconCreateException(
        description: 'Maximum attachments per message reached',
      );
    }
    final position = count;
    final label = sanitizedAttachmentBaseName(uploadFilename ?? 'file');
    var mime = _normalizeAttachmentMime(uploadMimeType, label);
    final sniffedMime = inferImageMimeFromLeadingBytes(bytes);
    if (sniffedMime != null) {
      mime = sniffedMime;
    }
    final useImagePipeline =
        sniffedMime != null || _attachmentLooksLikeImage(mime, label);
    if (useImagePipeline) {
      final imageId = await _imageRepository.put(
        authorId: userId,
        bytes: Stream.value(bytes),
      );
      await _tasksRepository.schedule(
        TaskEntity(
          details: TaskCalculateImageHashDetails(imageId: imageId),
        ),
      );
      await _room.insertRoomMessageAttachmentImage(
        attachmentId: attachmentId,
        messageId: messageId,
        position: position,
        imageId: imageId,
        mime: mime,
        sizeBytes: bytes.length,
        displayName: label,
        mutatingUserId: mutatingUserId,
      );
    } else {
      final safeObjectName = sanitizedAttachmentBaseName(label);
      final storagePath =
          '$kRoomAttachmentsPath/$userId/$attachmentId/$safeObjectName';
      final meta = <String, String>{
        kHeaderContentType: mime,
      };
      final acl = env.kS3PutObjectAclValue;
      if (acl != null) {
        meta['x-amz-acl'] = acl;
      }
      await _remoteStorage.putObject(
        storagePath,
        Stream.value(bytes),
        metadata: meta,
      );
      await _room.insertRoomMessageAttachmentFile(
        attachmentId: attachmentId,
        messageId: messageId,
        position: position,
        storagePath: storagePath,
        mime: mime,
        sizeBytes: bytes.length,
        displayName: safeObjectName,
        mutatingUserId: mutatingUserId,
      );
    }
  }

  static bool _attachmentLooksLikeImage(String mime, String fileLabel) {
    final m = mime.toLowerCase().trim();
    if (m.startsWith('image/')) {
      return true;
    }
    final lower = fileLabel.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.heic') ||
        lower.endsWith('.heif');
  }

  static String _normalizeAttachmentMime(String? rawMime, String fileLabel) {
    final t = rawMime?.trim();
    if (t != null && t.isNotEmpty) {
      return t;
    }
    final lower = fileLabel.toLowerCase();
    if (lower.endsWith('.pdf')) {
      return 'application/pdf';
    }
    if (lower.endsWith('.txt')) {
      return 'text/plain';
    }
    if (_attachmentLooksLikeImage('application/octet-stream', fileLabel)) {
      return 'image/jpeg';
    }
    return 'application/octet-stream';
  }
}
