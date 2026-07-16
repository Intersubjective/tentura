import 'dart:typed_data';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/domain/port/beacon_fact_card_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_port.dart';
import 'package:tentura_server/domain/port/remote_storage_port.dart';
import 'package:tentura_server/domain/port/upload_quota_repository_port.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_record.dart';
import 'package:tentura_server/domain/entity/task_entity.dart';
import 'package:tentura_server/domain/port/image_repository_port.dart';
import 'package:tentura_server/domain/port/task_repository_port.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/exception.dart';

import 'package:tentura_root/utils/infer_image_mime_from_bytes.dart';

import 'package:tentura_server/domain/util/attachment_filename.dart';
import 'package:tentura_server/domain/util/room_attachment_storage_key.dart';
import 'package:tentura_server/utils/id.dart';
import 'package:tentura_server/utils/read_uint8_stream_with_limit.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '_use_case_base.dart';

/// Room coordination: admission, steward, messages (server-side rules).
// TODO(contract): tighten permissions with visibility / forward graph —
// current checks are author-or-steward or admitted-member only.
@Singleton(order: 2)
final class BeaconRoomCase extends UseCaseBase {
  BeaconRoomCase(
    this._room,
    this._items,
    this._factCards,
    BeaconRoomNotificationPort legacyNotificationPort,
    this._imageRepository,
    this._tasksRepository,
    this._remoteStorage,
    this._pollingRepository,
    this._uploadQuota, {
    AttentionIntentCase? attentionIntents,
    TransactionalAttentionCase? attention,
    required super.env,
    required super.logger,
  }) : _attentionIntents = attentionIntents,
       _attention = attention;

  final BeaconRoomRepositoryPort _room;

  final CoordinationItemRepositoryPort _items;

  final BeaconFactCardRepositoryPort _factCards;

  final AttentionIntentCase? _attentionIntents;

  final TransactionalAttentionCase? _attention;

  final ImageRepositoryPort _imageRepository;

  final TaskRepositoryPort _tasksRepository;

  final RemoteStoragePort _remoteStorage;

  final PollingRepositoryPort _pollingRepository;

  final UploadQuotaRepositoryPort _uploadQuota;

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
    final p = await _room.findParticipant(beaconId: beaconId, userId: userId);
    return p?.roomAccess == RoomAccessBits.admitted;
  }

  bool _isItemParticipant(CoordinationItemRecord item, String userId) =>
      item.creatorId == userId ||
      item.targetPersonId == userId ||
      item.acceptedById == userId;

  Future<void> _rejectPlanItemThread(String threadItemId) async {
    final item = await _items.getById(threadItemId);
    if (item != null && item.kind == coordinationItemKindPlan) {
      throw const IdWrongException(
        description: 'Plan items do not support item discussion threads',
      );
    }
  }

  Future<bool> _canAccessThread({
    required String beaconId,
    required String userId,
    required String threadItemId,
  }) async {
    if (await _canUseRoom(beaconId: beaconId, userId: userId)) {
      return true;
    }
    final item = await _items.getById(threadItemId);
    if (item == null || item.beaconId != beaconId) {
      return false;
    }
    return _isItemParticipant(item, userId);
  }

  Future<bool> _canMutateMessage({
    required String beaconId,
    required String userId,
    required BeaconRoomMessageRecord msg,
  }) async {
    final tid = msg.threadItemId;
    if (tid == null || tid.isEmpty) {
      return _canUseRoom(beaconId: beaconId, userId: userId);
    }
    await _rejectPlanItemThread(tid);
    return _canAccessThread(
      beaconId: beaconId,
      userId: userId,
      threadItemId: tid,
    );
  }

  void _assertBodyWithinLimit(String trimmedBody) {
    if (trimmedBody.length > kMaxRoomMessageBodyLength) {
      throw const BeaconCreateException(
        description: 'Message is too long',
      );
    }
  }

  /// Spam control: reject when an author has posted too many room messages
  /// within the configured trailing window (across all beacons/threads).
  Future<void> _enforceMessageRateLimit(String userId) async {
    final recent = await _room.countRecentMessagesByAuthor(
      authorId: userId,
      window: env.roomMessageRateWindow,
    );
    if (recent >= env.roomMessageMaxPerUser) {
      logger.info('room message rate-limited for user $userId');
      throw const RateLimitedException(
        description: 'Too many messages sent, please slow down',
      );
    }
  }

  Future<Map<String, Object?>> createMessage({
    required String beaconId,
    required String userId,
    required String body,
    String? replyToMessageId,
    String? threadItemId,
    Stream<Uint8List>? attachmentBytes,
    String? attachmentFilename,
    String? attachmentMimeType,
  }) async {
    final tid = threadItemId?.trim();
    final inThread = tid != null && tid.isNotEmpty;
    CoordinationItemRecord? threadItem;
    if (inThread) {
      await _rejectPlanItemThread(tid);
      final allowed = await _canAccessThread(
        beaconId: beaconId,
        userId: userId,
        threadItemId: tid,
      );
      if (!allowed) {
        throw const UnauthorizedException(
          description: 'Room or item thread access required',
        );
      }
      final item = await _items.getById(tid);
      if (item == null || item.beaconId != beaconId) {
        throw IdNotFoundException(
          id: tid,
          description: 'Coordination item not found',
        );
      }
      threadItem = item;
    } else {
      final allowed = await _canUseRoom(beaconId: beaconId, userId: userId);
      if (!allowed) {
        throw const UnauthorizedException(
          description: 'Room access required',
        );
      }
    }
    BeaconRoomMessageRecord? repliedMessage;
    if (replyToMessageId != null && replyToMessageId.isNotEmpty) {
      repliedMessage = await _room.getRoomMessageById(replyToMessageId);
      if (repliedMessage == null ||
          repliedMessage.beaconId != beaconId ||
          repliedMessage.threadItemId != (inThread ? tid : null)) {
        throw const IdWrongException(
          description: 'Reply must reference a message in the same chat scope',
        );
      }
    }
    await _enforceMessageRateLimit(userId);
    final trimmed = body.trim();
    _assertBodyWithinLimit(trimmed);
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
    final mentionIds = trimmed.isEmpty
        ? const <String>[]
        : await _room.resolveMentionUserIdsForBeacon(
            beaconId: beaconId,
            body: trimmed,
          );
    final directedRecipientIds = <String>{
      ...mentionIds,
      if (repliedMessage != null) repliedMessage.authorId,
      if (threadItem?.targetPersonId case final target?) target,
    }..removeWhere((id) => id.isEmpty || id == userId);

    Future<Map<String, Object?>> persist(
      AttentionTransaction? transaction,
    ) async {
      final row = await _room.insertRoomMessage(
        beaconId: beaconId,
        authorId: userId,
        body: trimmed,
        replyToMessageId: replyToMessageId,
        threadItemId: inThread ? tid : null,
        mentions: mentionIds,
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
      if (transaction != null) {
        await transaction.record(
          await _attentionIntents!.roomMessagePosted(
            beaconId: beaconId,
            messageId: row.id,
            actorUserId: userId,
            recipientUserIds: directedRecipientIds,
            excerpt: trimmed.isEmpty ? 'Shared an attachment' : trimmed,
            threadItemId: inThread ? tid : null,
            sourceEventKey: 'room_message:${row.id}',
          ),
        );
      }
      return {'id': row.id, 'beaconId': row.beaconId};
    }

    if (directedRecipientIds.isEmpty) {
      return persist(null);
    }
    return _attention!.runAction(
      actorUserId: userId,
      action: persist,
    );
  }

  Future<List<Map<String, Object?>>> listMessages({
    required String beaconId,
    required String userId,
    String? beforeIso,
    String? threadItemId,
  }) async {
    final tid = threadItemId?.trim();
    final inThread = tid != null && tid.isNotEmpty;
    if (inThread) {
      await _rejectPlanItemThread(tid);
      final allowed = await _canAccessThread(
        beaconId: beaconId,
        userId: userId,
        threadItemId: tid,
      );
      if (!allowed) {
        throw const UnauthorizedException(
          description: 'Room or item thread access required',
        );
      }
    } else {
      final allowed = await _canUseRoom(beaconId: beaconId, userId: userId);
      if (!allowed) {
        throw const UnauthorizedException(
          description: 'Room access required',
        );
      }
    }
    final before = beforeIso != null ? DateTime.tryParse(beforeIso) : null;
    return _room.listMessagesEnriched(
      beaconId: beaconId,
      viewerUserId: userId,
      threadItemId: inThread ? tid : null,
      before: before,
    );
  }

  /// Resolves one exact Chat target after checking the target's actual scope.
  Future<Map<String, Object?>> roomMessageTarget({
    required String beaconId,
    required String messageId,
    required String userId,
  }) async {
    final message = await _room.getRoomMessageById(messageId);
    if (message == null || message.beaconId != beaconId) {
      throw IdNotFoundException(
        id: messageId,
        description: 'Chat message not on this request',
      );
    }
    final threadItemId = message.threadItemId?.trim();
    final allowed = threadItemId == null || threadItemId.isEmpty
        ? await _canUseRoom(beaconId: beaconId, userId: userId)
        : await _canAccessThread(
            beaconId: beaconId,
            userId: userId,
            threadItemId: threadItemId,
          );
    if (!allowed) {
      throw const UnauthorizedException(
        description: 'Room or item thread access required',
      );
    }
    final target = await _room.roomMessageTarget(
      beaconId: beaconId,
      messageId: messageId,
      viewerUserId: userId,
    );
    if (target == null) {
      throw IdNotFoundException(id: messageId);
    }
    return target;
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
        'currentLine': '',
        'openBlockerId': null,
        'openBlockerTitle': null,
        'lastRoomMeaningfulChange': null,
        'updatedAt': nowIso,
        'updatedBy': null,
      };
    }
    final openBlocker = await _findOpenCoordinationBlocker(
      beaconId,
      viewerUserId: userId,
    );
    return {
      'beaconId': row.beaconId,
      'currentLine': row.currentLine,
      'openBlockerId': openBlocker?.id,
      'openBlockerTitle': openBlocker?.title,
      'lastRoomMeaningfulChange': row.lastRoomMeaningfulChange,
      'updatedAt': row.updatedAt.toIso8601String(),
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
          'currentLine': null,
          'lastRoomMeaningfulChange': null,
          'nextMoveText': null,
          'roomUnreadCount': 0,
          'lastSeenAt': null,
          'openBlockerTitle': null,
          ..._emptyOpenBlockerBatchFields(),
          'publicFactSnippet': factSnippet,
        });
        continue;
      }
      final p = await _room.findParticipant(beaconId: bid, userId: userId);
      final st = await _room.getBeaconRoomState(bid);
      final seenAt = await _room.getMainRoomLastSeen(
        beaconId: bid,
        userId: userId,
      );
      final unread = await _room.countRoomMessagesAfter(
        beaconId: bid,
        after: seenAt,
        excludeAuthorId: userId,
      );
      final openBlocker = await _findOpenCoordinationBlocker(
        bid,
        viewerUserId: userId,
      );
      final blockerFields = await _openBlockerBatchFields(openBlocker);
      out.add({
        'beaconId': bid,
        'isRoomMember': true,
        'currentLine': st?.currentLine,
        'lastRoomMeaningfulChange': st?.lastRoomMeaningfulChange,
        'nextMoveText': p?.nextMoveText,
        'roomUnreadCount': unread,
        'lastSeenAt': seenAt?.toUtc().toIso8601String(),
        'openBlockerTitle': openBlocker?.title,
        ...blockerFields,
        'publicFactSnippet': factSnippet,
      });
    }
    return out;
  }

  Future<List<Map<String, Object?>>> listActivityEvents({
    required String beaconId,
    required String userId,
  }) async {
    final allowed = await _canUseRoom(beaconId: beaconId, userId: userId);
    final rows = await _room.listActivityEvents(beaconId: beaconId);
    if (allowed) return rows;
    return [
      for (final r in rows)
        if (r['visibility'] == BeaconActivityEventVisibilityBits.public) r,
    ];
  }

  Future<List<MyWorkLastActivityEventRow>> myWorkLastActivityEventsByBeaconIds({
    required String userId,
    required List<String> beaconIds,
  }) async {
    final unique = beaconIds.toSet().toList();
    if (unique.isEmpty) {
      return const [];
    }
    final slice = unique.length > 80 ? unique.sublist(0, 80) : unique;
    return _room.latestActivityEventsByBeaconIds(
      beaconIds: slice,
      viewerUserId: userId,
    );
  }

  /// Marks a room message with the semantic "done" marker (no blocker resolution).
  Future<bool> roomMessageMarkSemanticDone({
    required String beaconId,
    required String userId,
    required String messageId,
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
        description: 'Chat message not on this request',
      );
    }
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
    return true;
  }

  Future<Map<String, Object?>> markBeaconRoomSeen({
    required String beaconId,
    required String userId,
    String? threadItemId,
    String? readThroughAtIso,
  }) async {
    final tid = threadItemId?.trim();
    final inThread = tid != null && tid.isNotEmpty;
    if (inThread) {
      await _rejectPlanItemThread(tid);
      final allowed = await _canAccessThread(
        beaconId: beaconId,
        userId: userId,
        threadItemId: tid,
      );
      if (!allowed) {
        throw const UnauthorizedException(
          description: 'Room or item thread access required',
        );
      }
    } else {
      final allowed = await _canUseRoom(beaconId: beaconId, userId: userId);
      if (!allowed) {
        throw const UnauthorizedException(
          description: 'Room access required',
        );
      }
    }
    final parsedReadThrough =
        readThroughAtIso != null && readThroughAtIso.trim().isNotEmpty
        ? DateTime.tryParse(readThroughAtIso.trim())
        : null;
    var at = parsedReadThrough ?? DateTime.timestamp();
    if (!inThread) {
      final latest = await _room.latestMainRoomMessageCreatedAt(beaconId);
      if (latest != null) {
        if (latest.isAfter(at)) {
          at = latest;
        } else if (at.isAfter(latest)) {
          at = latest;
        }
      }
      final existing = await _room.getMainRoomLastSeen(
        beaconId: beaconId,
        userId: userId,
      );
      if (existing != null && existing.isAfter(at)) {
        at = existing;
      }
    }
    await _room.markBeaconRoomSeen(
      userId: userId,
      beaconId: beaconId,
      threadItemId: inThread ? tid : null,
      at: at,
    );
    return {
      'beaconId': beaconId,
      'threadItemId': inThread ? tid : null,
      'seenAt': at.toUtc().toIso8601String(),
    };
  }

  Future<Map<String, Object?>> beaconParticipantRoomSeen({
    required String beaconId,
    required String userId,
    String? readThroughAtIso,
  }) => markBeaconRoomSeen(
    beaconId: beaconId,
    userId: userId,
    readThroughAtIso: readThroughAtIso,
  );

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
    final userIds = rows.map((r) => r.userId).toSet().toList();
    final lastSeenByUserId = await _room.mainRoomLastSeenByUserIds(
      beaconId: beaconId,
      userIds: userIds,
    );
    final titlesByUserId = userIds.isEmpty
        ? <String, String>{}
        : await _room.userTitlesByIds(userIds);

    final handlesByUserId = userIds.isEmpty
        ? <String, String>{}
        : await _room.userHandlesByIds(userIds);

    final picMetaByUserId = userIds.isEmpty
        ? const <
            String,
            ({
              bool hasPicture,
              int picHeight,
              int picWidth,
              String blurHash,
              String imageId,
            })
          >{}
        : await _room.userPicMetaByIds(userIds);
    final helpTypesByUserId = await _room.helpTypesByUserId(beaconId);
    return rows
        .map(
          (r) => <String, Object?>{
            'id': r.id,
            'beaconId': r.beaconId,
            'userId': r.userId,
            'userTitle': titlesByUserId[r.userId] ?? '',
            'userHandle': handlesByUserId[r.userId] ?? '',
            'userHasPicture': picMetaByUserId[r.userId]?.hasPicture ?? false,
            'userPicHeight': picMetaByUserId[r.userId]?.picHeight ?? 0,
            'userPicWidth': picMetaByUserId[r.userId]?.picWidth ?? 0,
            'userBlurHash': picMetaByUserId[r.userId]?.blurHash ?? '',
            'userImageId': picMetaByUserId[r.userId]?.imageId ?? '',
            'role': r.role,
            'status': r.status,
            'roomAccess': r.roomAccess,
            'offerNote': r.offerNote,
            'nextMoveText': r.nextMoveText,
            'nextMoveStatus': r.nextMoveStatus,
            'nextMoveSource': r.nextMoveSource,
            'linkedMessageId': r.linkedMessageId,
            'lastSeenRoomAt': lastSeenByUserId[r.userId]
                ?.toUtc()
                .toIso8601String(),
            'helpType': helpTypesByUserId[r.userId],
            'createdAt': r.createdAt.toIso8601String(),
            'updatedAt': r.updatedAt.toIso8601String(),
          },
        )
        .toList();
  }

  Future<void> offerHelp({
    required String beaconId,
    required String userId,
    required String note,
  }) async {
    await _attention!.runAction<void>(
      actorUserId: userId,
      action: (transaction) async {
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
        await transaction.record(
          await _attentionIntents!.helpOfferSubmitted(
            beaconId: beaconId,
            helpOffererId: userId,
            authorId: author ?? '',
            moderatorUserIds: moderators,
            sourceEventKey: 'room_help_offer:${generateId('A')}',
          ),
        );
      },
    );
  }

  Future<void> admit({
    required String beaconId,
    required String participantUserId,
    required String actorUserId,
  }) async {
    final author = await _room.isBeaconAuthor(
      beaconId: beaconId,
      userId: actorUserId,
    );
    final steward = await _room.isBeaconSteward(
      beaconId: beaconId,
      userId: actorUserId,
    );
    if (!author && !steward) {
      throw const UnauthorizedException(description: 'Author or steward only');
    }
    await _attention!.runAction<void>(
      actorUserId: actorUserId,
      action: (transaction) async {
        await _room.admitParticipant(
          beaconId: beaconId,
          participantUserId: participantUserId,
          actorUserId: actorUserId,
        );
        await transaction.record(
          await _attentionIntents!.offerAccepted(
            receiverId: participantUserId,
            beaconId: beaconId,
            actorUserId: actorUserId,
            sourceEventKey: 'room_admission:${generateId('A')}',
          ),
        );
      },
    );
  }

  Future<void> stewardPromote({
    required String beaconId,
    required String stewardUserId,
    required String authorUserId,
  }) async {
    final author = await _room.isBeaconAuthor(
      beaconId: beaconId,
      userId: authorUserId,
    );
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
    final msg = await _room.getRoomMessageById(messageId);
    if (msg == null || msg.beaconId != beaconId) {
      throw IdNotFoundException(
        id: messageId,
        description: 'Room message not found',
      );
    }
    final allowed = await _canMutateMessage(
      beaconId: beaconId,
      userId: userId,
      msg: msg,
    );
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

  Future<bool> addMessageAttachment({
    required String beaconId,
    required String userId,
    required String messageId,
    required Stream<Uint8List> attachmentBytes,
    String? attachmentFilename,
    String? attachmentMimeType,
  }) async {
    final msg = await _room.getRoomMessageById(messageId);
    if (msg == null || msg.beaconId != beaconId) {
      throw IdNotFoundException(
        id: messageId,
        description: 'Room message not found',
      );
    }
    final canMutate = await _canMutateMessage(
      beaconId: beaconId,
      userId: userId,
      msg: msg,
    );
    if (!canMutate) {
      throw const UnauthorizedException(description: 'Room access required');
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

  Future<bool> deleteMessage({
    required String beaconId,
    required String messageId,
    required String userId,
  }) async {
    final msg = await _room.getRoomMessageById(messageId);
    if (msg == null || msg.beaconId != beaconId) {
      throw IdNotFoundException(
        id: messageId,
        description: 'Room message not found',
      );
    }
    final allowed = await _canMutateMessage(
      beaconId: beaconId,
      userId: userId,
      msg: msg,
    );
    if (!allowed) {
      throw const UnauthorizedException(description: 'Room access required');
    }
    if (msg.authorId != userId) {
      throw const UnauthorizedException(
        description: 'Only the message author can delete messages',
      );
    }
    await _room.deleteRoomMessage(messageId: messageId);
    return true;
  }

  Future<bool> editMessage({
    required String beaconId,
    required String messageId,
    required String userId,
    required String newBody,
  }) async {
    final msg = await _room.getRoomMessageById(messageId);
    if (msg == null || msg.beaconId != beaconId) {
      throw IdNotFoundException(
        id: messageId,
        description: 'Room message not found',
      );
    }
    final allowed = await _canMutateMessage(
      beaconId: beaconId,
      userId: userId,
      msg: msg,
    );
    if (!allowed) {
      throw const UnauthorizedException(description: 'Room access required');
    }
    if (msg.authorId != userId) {
      throw const UnauthorizedException(
        description: 'Only the message author can edit messages',
      );
    }
    final trimmed = newBody.trim();
    if (trimmed.isEmpty) {
      throw const BeaconCreateException(
        description: 'Message body cannot be empty',
      );
    }
    _assertBodyWithinLimit(trimmed);
    final mentionIds = await _room.resolveMentionUserIdsForBeacon(
      beaconId: beaconId,
      body: trimmed,
    );
    await _room.updateMessage(
      messageId: messageId,
      newBody: trimmed,
      mentions: mentionIds,
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
    final roomOk = await _canMutateMessage(
      beaconId: msg.beaconId,
      userId: userId,
      msg: msg,
    );
    if (!roomOk) {
      throw const UnauthorizedException(description: 'Room access required');
    }
    final bytes = await _remoteStorage.getObject(row.fileUrl!);
    final name = row.fileName.trim().isEmpty ? 'download' : row.fileName.trim();
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
    final attachmentId = generateId('A');
    final displayName = attachmentDisplayName(uploadFilename ?? 'file');
    var mime = _normalizeAttachmentMime(uploadMimeType, displayName);
    final sniffedMime = inferImageMimeFromLeadingBytes(bytes);
    if (sniffedMime != null) {
      mime = sniffedMime;
    }
    final useImagePipeline =
        sniffedMime != null || _attachmentLooksLikeImage(mime, displayName);
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
        displayName: displayName,
        mutatingUserId: mutatingUserId,
      );
    } else {
      // Image attachments reserve quota inside ImageRepository.put; file
      // attachments are written straight to storage, so reserve here.
      final withinDailyCap = await _uploadQuota.tryReserveDailyBytes(
        userId: userId,
        bytes: bytes.length,
        dailyCapBytes: env.uploadDailyCapBytes,
      );
      if (!withinDailyCap) {
        throw const RateLimitedException(
          description: 'Daily upload limit reached, try again tomorrow',
        );
      }
      final storagePath = roomAttachmentStorageKey(bytes);
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
        displayName: displayName,
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

  Future<Map<String, Object?>> createPoll({
    required String beaconId,
    required String userId,
    required String question,
    required List<String> variants,
    String? pollType,
    bool? isAnonymous,
    bool? allowRevote,
  }) async {
    final allowed = await _canUseRoom(beaconId: beaconId, userId: userId);
    if (!allowed) {
      throw const UnauthorizedException(description: 'Room access required');
    }
    await _enforceMessageRateLimit(userId);
    final trimmedQuestion = question.trim();
    if (trimmedQuestion.isEmpty) {
      throw const BeaconCreateException(
        description: 'Poll question is required',
      );
    }
    final validVariants = variants
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toList();
    if (validVariants.length < 2) {
      throw const BeaconCreateException(
        description: 'At least 2 poll variants required',
      );
    }
    final resolvedPollType = pollType ?? 'single';
    if (!const {'single', 'multiple', 'range'}.contains(resolvedPollType)) {
      throw const BeaconCreateException(description: 'Invalid poll type');
    }
    final pollingId = await _pollingRepository.createWithVariants(
      authorId: userId,
      question: trimmedQuestion,
      variants: validVariants,
      pollType: resolvedPollType,
      isAnonymous: isAnonymous ?? true,
      allowRevote: allowRevote ?? true,
    );
    return _room.insertAndEnrichPollMessage(
      beaconId: beaconId,
      authorId: userId,
      linkedPollingId: pollingId,
      viewerUserId: userId,
    );
  }

  Future<CoordinationItemRecord?> _findOpenCoordinationBlocker(
    String beaconId, {
    required String viewerUserId,
  }) async {
    final rows = await _items.listByBeacon(
      beaconId,
      viewerUserId: viewerUserId,
      kind: coordinationItemKindBlocker,
      status: coordinationItemStatusOpen,
    );
    return rows.isEmpty ? null : rows.first.item;
  }

  Map<String, Object?> _emptyOpenBlockerBatchFields() => {
    'openBlockerCreatorId': null,
    'openBlockerTargetPersonId': null,
    'openBlockerResponsibleUserId': null,
    'openBlockerCreatedAt': null,
    'openBlockerCreatorDisplayName': null,
    'openBlockerCreatorImageId': null,
    'openBlockerCreatorHasPicture': false,
  };

  Future<Map<String, Object?>> _openBlockerBatchFields(
    CoordinationItemRecord? openBlocker,
  ) async {
    if (openBlocker == null) {
      return _emptyOpenBlockerBatchFields();
    }
    final creatorId = openBlocker.creatorId;
    final target = openBlocker.targetPersonId;
    final responsible = target != null && target.isNotEmpty
        ? target
        : creatorId;
    final titles = await _room.userTitlesByIds([creatorId]);
    final pics = await _room.userPicMetaByIds([creatorId]);
    final pic = pics[creatorId];
    return {
      'openBlockerCreatorId': creatorId,
      'openBlockerTargetPersonId': target,
      'openBlockerResponsibleUserId': responsible,
      'openBlockerCreatedAt': openBlocker.createdAt.toUtc().toIso8601String(),
      'openBlockerCreatorDisplayName': titles[creatorId] ?? '',
      'openBlockerCreatorImageId': pic?.imageId,
      'openBlockerCreatorHasPicture': pic?.hasPicture ?? false,
    };
  }
}
