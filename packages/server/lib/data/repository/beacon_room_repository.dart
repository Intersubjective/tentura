import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/consts/beacon_participant_status_bits.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/utils/room_mention_utils.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_entity.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart';

/// Beacon Room messages + participants — Postgres via Drift.
@lazySingleton
class BeaconRoomRepository {
  const BeaconRoomRepository(this._db);

  final TenturaDb _db;

  Future<List<BeaconRoomMessage>> listMessages({
    required String beaconId,
    String? threadItemId,
    DateTime? before,
    int limit = 50,
  }) async {
    Expression<bool> threadFilter($BeaconRoomMessagesTable m) {
      final tid = threadItemId;
      if (tid == null) {
        return m.threadItemId.isNull();
      }
      return m.threadItemId.equals(tid);
    }

    if (before == null) {
      return (_db.select(_db.beaconRoomMessages)
            ..where((m) => m.beaconId.equals(beaconId) & threadFilter(m))
            ..orderBy([
              (m) => OrderingTerm(
                    expression: m.createdAt,
                    mode: OrderingMode.desc,
                  ),
            ])
            ..limit(limit))
          .get();
    }
    return (_db.select(_db.beaconRoomMessages)
          ..where((m) =>
              m.beaconId.equals(beaconId) &
              threadFilter(m) &
              m.createdAt.isSmallerThanValue(PgDateTime(before)))
          ..orderBy([
            (m) =>
                OrderingTerm(expression: m.createdAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
  }

  /// Same shape as the `attachmentsJson` field returned by
  /// [BeaconRoomRepository.listMessagesEnriched]: one JSON array per requested
  /// message id (keyed by message id).
  Future<Map<String, String>> attachmentsJsonByMessageIds(
    Iterable<String> messageIds,
  ) async {
    final ids = messageIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) {
      return {};
    }

    final attachmentRows = await (_db.select(_db.beaconRoomMessageAttachments)
          ..where((a) => a.messageId.isIn(ids))
          ..orderBy([
            (a) => OrderingTerm(expression: a.position),
          ]))
        .get();

    final attachmentsByMessageId =
        <String, List<BeaconRoomMessageAttachment>>{};
    for (final row in attachmentRows) {
      attachmentsByMessageId.putIfAbsent(row.messageId, () => []).add(row);
    }

    final attachmentImageUuidList = <UuidValue>[
      for (final row in attachmentRows)
        if (row.kind == BeaconRoomMessageAttachmentKind.image &&
            row.imageId != null)
          row.imageId!,
    ];

    final attachmentImageByUuid = <UuidValue, Image>{};
    if (attachmentImageUuidList.isNotEmpty) {
      final aimgs =
          await _db.managers.images
              .filter((i) => i.id.isIn(attachmentImageUuidList))
              .get();
      for (final img in aimgs) {
        attachmentImageByUuid[img.id] = img;
      }
    }

    final out = <String, String>{};
    for (final messageId in ids) {
      final rows = attachmentsByMessageId[messageId];
      if (rows == null || rows.isEmpty) {
        out[messageId] = '[]';
        continue;
      }
      final items = <Map<String, Object?>>[];
      for (final row in rows) {
        if (row.kind == BeaconRoomMessageAttachmentKind.image &&
            row.imageId != null) {
          final img = attachmentImageByUuid[row.imageId!];
          items.add({
            'id': row.id,
            'kind': row.kind,
            'position': row.position,
            'mime': row.mime,
            'sizeBytes': row.sizeBytes,
            'fileName': row.fileName,
            'imageId': img?.id.uuid ?? '',
            'imageAuthorId': img?.authorId ?? '',
            'blurHash': img?.hash ?? '',
            'width': img?.width ?? 0,
            'height': img?.height ?? 0,
          });
        } else {
          items.add({
            'id': row.id,
            'kind': row.kind,
            'position': row.position,
            'mime': row.mime,
            'sizeBytes': row.sizeBytes,
            'fileName': row.fileName,
          });
        }
      }
      out[messageId] = jsonEncode(items);
    }
    return out;
  }

  /// Room messages with author profile projection + reaction aggregates for V2
  /// `RoomMessageList`.
  ///
  /// Uses drift `listMessages` for ordering/filter (same SQL path as before beacon
  /// room enrichment). Raw SQL with `ORDER BY`/`LIMIT` + drift placeholders hit a
  /// Postgres parser issue (`syntax error at or near "ORDER"`).
  Future<List<Map<String, Object?>>> listMessagesEnriched({
    required String beaconId,
    required String viewerUserId,
    String? threadItemId,
    DateTime? before,
    int limit = 50,
  }) async {
    final msgs = await listMessages(
      beaconId: beaconId,
      threadItemId: threadItemId,
      before: before,
      limit: limit,
    );
    if (msgs.isEmpty) {
      return [];
    }

    final authorIds = msgs.map((m) => m.authorId).toSet().toList();
    final users =
        await _db.managers.users.filter((u) => u.id.isIn(authorIds)).get();
    final userById = {for (final u in users) u.id: u};

    final ids = msgs.map((m) => m.id).toList();
    final reactionRows = await (_db.select(_db.beaconRoomMessageReactions)
          ..where((r) => r.messageId.isIn(ids)))
        .get();

    final reactorIds = reactionRows.map((r) => r.userId).toSet();
    final missingReactorUserIds =
        reactorIds.difference(userById.keys.toSet()).toList();
    if (missingReactorUserIds.isNotEmpty) {
      final moreUsers = await _db.managers.users
          .filter((u) => u.id.isIn(missingReactorUserIds))
          .get();
      for (final u in moreUsers) {
        userById[u.id] = u;
      }
    }

    final imageUuidIds = {
      for (final u in userById.values)
        if (u.imageId case final UuidValue id) id,
    }.toList();

    final imageByUuid = <UuidValue, Image>{};
    if (imageUuidIds.isNotEmpty) {
      final imgs =
          await _db.managers.images.filter((i) => i.id.isIn(imageUuidIds)).get();
      for (final img in imgs) {
        imageByUuid[img.id] = img;
      }
    }

    final countsByMessage = <String, Map<String, int>>{};
    final viewerEmojisByMessage = <String, List<String>>{};
    /// Per message, per emoji, ordered reactor profile rows (newest first).
    final reactorsByMessage =
        <String, Map<String, List<Map<String, Object?>>>>{};

    Map<String, Object?> reactorProfileJson(String uid) {
      final userRow = userById[uid];
      final displayName = userRow?.displayName ?? '';
      final imgUuid = userRow?.imageId;
      final image = imgUuid != null ? imageByUuid[imgUuid] : null;
      final hasPicture = imgUuid != null && image != null;
      final picHeight = image?.height ?? 0;
      final picWidth = image?.width ?? 0;
      final blurHash = image?.hash ?? '';
      final imageId = image != null ? image.id.toString() : '';
      return <String, Object?>{
        'id': uid,
        'displayName': displayName,
        'hasPicture': hasPicture,
        'imageId': imageId,
        'blurHash': blurHash,
        'picHeight': picHeight,
        'picWidth': picWidth,
      };
    }

    final sortedReactions = [...reactionRows]
      ..sort(
        (a, b) => b.createdAt.dateTime.compareTo(a.createdAt.dateTime),
      );
    for (final rr in sortedReactions) {
      final mid = rr.messageId;
      final emoji = rr.emoji;
      final uid = rr.userId;

      final cm = countsByMessage.putIfAbsent(mid, () => <String, int>{});
      cm[emoji] = (cm[emoji] ?? 0) + 1;

      if (uid == viewerUserId) {
        viewerEmojisByMessage.putIfAbsent(mid, () => <String>[]).add(emoji);
      }

      final byEmoji =
          reactorsByMessage.putIfAbsent(mid, () => <String, List<Map<String, Object?>>>{});
      final list = byEmoji.putIfAbsent(emoji, () => <Map<String, Object?>>[]);
      if (!list.any((m) => m['id'] == uid)) {
        list.add(reactorProfileJson(uid));
      }
    }

    String? reactionsJsonFor(String messageId) {
      final m = countsByMessage[messageId];
      if (m == null || m.isEmpty) {
        return null;
      }
      return jsonEncode(m);
    }

    String? myReactionFor(String messageId) {
      final list = viewerEmojisByMessage[messageId];
      if (list == null || list.isEmpty) {
        return null;
      }
      final unique = list.toSet().toList()..sort();
      return unique.join(',');
    }

    String? reactorsJsonFor(String messageId) {
      final byEmoji = reactorsByMessage[messageId];
      if (byEmoji == null || byEmoji.isEmpty) {
        return null;
      }
      final out = <String, List<Map<String, Object?>>>{};
      for (final e in byEmoji.entries) {
        if (e.value.isNotEmpty) {
          out[e.key] = e.value;
        }
      }
      if (out.isEmpty) {
        return null;
      }
      return jsonEncode(out);
    }

    Object? encodeSystemPayload(Object? raw) {
      if (raw == null) {
        return null;
      }
      if (raw is String) {
        return raw;
      }
      return jsonEncode(raw);
    }

    final attachmentsJsonByMid =
        await attachmentsJsonByMessageIds(ids);

    final pollDataJsonByMid = await _pollDataJsonByMessageIds(
      msgs: msgs,
      viewerUserId: viewerUserId,
    );

    final linkedItemIds = <String>{
      for (final m in msgs)
        if ((m.linkedItemId ?? '').isNotEmpty) m.linkedItemId!,
    }.toList();

    final linkedCoordinationItemById = <String, CoordinationItem>{};
    if (linkedItemIds.isNotEmpty) {
      final itemRows = await (_db.select(_db.coordinationItems)
            ..where((t) => t.id.isIn(linkedItemIds)))
          .get();
      for (final row in itemRows) {
        linkedCoordinationItemById[row.id] = row;
      }
    }

    return msgs.map((m) {
      final id = m.id;
      final userRow = userById[m.authorId];
      final displayName = userRow?.displayName ?? '';
      final imgUuid = userRow?.imageId;
      final image = imgUuid != null ? imageByUuid[imgUuid] : null;
      final authorHasPicture = imgUuid != null && image != null;
      final authorPicHeight = image?.height ?? 0;
      final authorPicWidth = image?.width ?? 0;
      final authorBlurHash = image?.hash ?? '';
      final authorImageId = image != null ? image.id.toString() : '';

      final linkedId = m.linkedItemId;
      final linkedRow =
          linkedId != null ? linkedCoordinationItemById[linkedId] : null;

      return <String, Object?>{
        'id': id,
        'beaconId': m.beaconId,
        'authorId': m.authorId,
        'body': m.body,
        'createdAt': m.createdAt.dateTime.toUtc().toIso8601String(),
        'editedAt': m.editedAt?.dateTime.toUtc().toIso8601String(),
        'semanticMarker': m.semanticMarker,
        'linkedBlockerId': linkedRow != null &&
                linkedRow.kind == coordinationItemKindBlocker
            ? linkedId
            : null,
        'linkedFactCardId': m.linkedFactCardId,
        'linkedPollingId': m.linkedPollingId,
        'linkedItemId': linkedId,
        'linkedEventKind': m.linkedEventKind,
        if (linkedRow != null) ...<String, Object?>{
          'linkedItemKind': linkedRow.kind,
          'linkedItemStatus': linkedRow.status,
          'linkedItemTitle': linkedRow.title,
          'linkedItemBody': linkedRow.body,
          'linkedItemCreatorId': linkedRow.creatorId,
          'linkedItemCreatedAt':
              linkedRow.createdAt.dateTime.toUtc().toIso8601String(),
          'linkedItemUpdatedAt':
              linkedRow.updatedAt.dateTime.toUtc().toIso8601String(),
          'linkedItemLinkedMessageId': linkedRow.linkedMessageId,
          'linkedItemResolvedAt': linkedRow.resolvedAt?.dateTime
              .toUtc()
              .toIso8601String(),
        },
        'pollDataJson': pollDataJsonByMid[id],
        'systemPayloadJson': encodeSystemPayload(m.systemPayload),
        'authorTitle': displayName,
        'authorHasPicture': authorHasPicture,
        'authorPicHeight': authorPicHeight,
        'authorPicWidth': authorPicWidth,
        'authorBlurHash': authorBlurHash,
        'authorImageId': authorImageId,
        'reactionsJson': reactionsJsonFor(id),
        'myReaction': myReactionFor(id),
        'reactorsJson': reactorsJsonFor(id),
        'attachmentsJson':
            attachmentsJsonByMid[id] ?? '[]',
        // GraphQL `[String!]` — never emit null/empty slots (see migration 0060).
        'mentions': m.mentions.where((id) => id.isNotEmpty).toList(),
        'threadItemId': m.threadItemId,
      };
    }).toList();
  }

  Future<Map<String, String?>> _pollDataJsonByMessageIds({
    required List<BeaconRoomMessage> msgs,
    required String viewerUserId,
  }) async {
    final pollingByMessageId = <String, String>{};
    for (final m in msgs) {
      final pid = m.linkedPollingId;
      if (pid != null) pollingByMessageId[m.id] = pid;
    }
    if (pollingByMessageId.isEmpty) return {};

    final pollingIds = pollingByMessageId.values.toSet().toList();

    final pollings = await _db.managers.pollings
        .filter((p) => p.id.isIn(pollingIds))
        .get();

    final variants = await _db.managers.pollingVariants
        .filter((v) => v.pollingId.id.isIn(pollingIds))
        .get();

    final acts = await (_db.select(_db.pollingActs)
          ..where((a) => a.pollingId.isIn(pollingIds)))
        .get();

    // Viewer's voted variant IDs per poll (supports multiple/range)
    final myVariantIdsByPollingId = <String, List<String>>{};
    for (final a in acts) {
      if (a.authorId == viewerUserId) {
        myVariantIdsByPollingId.putIfAbsent(a.pollingId, () => []).add(a.pollingVariantId);
      }
    }

    // Vote counts per variant
    final countByVariantId = <String, int>{};
    for (final a in acts) {
      countByVariantId[a.pollingVariantId] =
          (countByVariantId[a.pollingVariantId] ?? 0) + 1;
    }

    // Distinct voter count per poll
    final votersByPollingId = <String, Set<String>>{};
    for (final a in acts) {
      votersByPollingId.putIfAbsent(a.pollingId, () => {}).add(a.authorId);
    }

    // Voter IDs per variant (for open polls)
    final voterIdsByVariantId = <String, List<String>>{};
    for (final a in acts) {
      voterIdsByVariantId.putIfAbsent(a.pollingVariantId, () => []).add(a.authorId);
    }

    // Sum and count of scores per variant (for range polls)
    final scoreSumByVariantId = <String, int>{};
    final scoreCountByVariantId = <String, int>{};
    for (final a in acts) {
      final s = a.score;
      if (s != null) {
        scoreSumByVariantId[a.pollingVariantId] =
            (scoreSumByVariantId[a.pollingVariantId] ?? 0) + s;
        scoreCountByVariantId[a.pollingVariantId] =
            (scoreCountByVariantId[a.pollingVariantId] ?? 0) + 1;
      }
    }

    final variantsByPollingId = <String, List<PollingVariant>>{};
    for (final v in variants) {
      variantsByPollingId.putIfAbsent(v.pollingId, () => []).add(v);
    }

    final pollingById = {for (final p in pollings) p.id: p};

    final out = <String, String?>{};
    for (final entry in pollingByMessageId.entries) {
      final msgId = entry.key;
      final pollId = entry.value;
      final polling = pollingById[pollId];
      if (polling == null) continue;

      final pvList = variantsByPollingId[pollId] ?? [];
      final myVariantIds = myVariantIdsByPollingId[pollId] ?? [];
      final totalVotes = votersByPollingId[pollId]?.length ?? 0;
      final viewerHasVoted = myVariantIds.isNotEmpty;
      final isRange = polling.pollType == 'range';
      // Only expose who voted when poll is open AND viewer has already voted
      final exposeVoters = !polling.isAnonymous && viewerHasVoted;

      out[msgId] = jsonEncode({
        'id': pollId,
        'question': polling.question,
        'pollType': polling.pollType,
        'isAnonymous': polling.isAnonymous,
        'allowRevote': polling.allowRevote,
        'myVariantIds': myVariantIds,
        'totalVotes': totalVotes,
        'variants': [
          for (final v in pvList)
            {
              'id': v.id,
              'description': v.description,
              'votesCount': countByVariantId[v.id] ?? 0,
              if (isRange)
                'avgScore': _avgScore(
                  scoreSumByVariantId[v.id],
                  scoreCountByVariantId[v.id],
                ),
              if (exposeVoters) 'voterIds': voterIdsByVariantId[v.id] ?? [],
            },
        ],
      });
    }
    return out;
  }

  double? _avgScore(int? sum, int? count) {
    if (sum == null || count == null || count == 0) return null;
    return sum / count;
  }

  Future<BeaconRoomMessage> insertRoomMessage({
    required String beaconId,
    required String authorId,
    required String body,
    String? replyToMessageId,
    String? threadItemId,
    String? linkedParticipantId,
    String? linkedPollingId,
    int? semanticMarker,
    Map<String, Object?>? systemPayload,
    List<String> mentions = const [],
  }) =>
      _db.withMutatingUser(authorId, () async {
        final id = generateId('R');
        return _db.managers.beaconRoomMessages.createReturning((o) => o(
              id: id,
              beaconId: beaconId,
              authorId: authorId,
              body: Value(body),
              replyToMessageId: Value(replyToMessageId),
              threadItemId: Value(threadItemId),
              linkedNextMoveId: Value(linkedParticipantId),
              linkedFactCardId: const Value.absent(),
              linkedPollingId: Value(linkedPollingId),
              semanticMarker: Value(semanticMarker),
              systemPayload: Value(systemPayload),
              mentions: Value(mentions),
              createdAt: const Value.absent(),
            ));
      });

  /// Creates a poll room message and returns the enriched row map for the GraphQL response.
  Future<Map<String, Object?>> insertAndEnrichPollMessage({
    required String beaconId,
    required String authorId,
    required String linkedPollingId,
    required String viewerUserId,
  }) async {
    final msg = await insertRoomMessage(
      beaconId: beaconId,
      authorId: authorId,
      body: '',
      linkedPollingId: linkedPollingId,
      semanticMarker: BeaconRoomSemanticMarker.poll,
    );
    final enriched = await listMessagesEnriched(
      beaconId: beaconId,
      viewerUserId: viewerUserId,
    );
    return enriched.firstWhere((m) => m['id'] == msg.id);
  }

  Future<void> updateParticipantNextMoveFields({
    required String actorUserId,
    required String participantRowId,
    required String nextMoveText,
    required int nextMoveSource,
    int? nextMoveStatus,
  }) =>
      _db.withMutatingUser(actorUserId, () async {
        await _db.managers.beaconParticipants
            .filter((r) => r.id.equals(participantRowId))
            .update(
              (o) => o(
                nextMoveText: Value(nextMoveText),
                nextMoveSource: Value(nextMoveSource),
                nextMoveStatus: Value(nextMoveStatus),
                updatedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
      });

  Future<void> updateMessage({
    required String messageId,
    required String newBody,
    required List<String> mentions,
  }) async {
    await _db.managers.beaconRoomMessages
        .filter((m) => m.id.equals(messageId))
        .update(
          (o) => o(
            body: Value(newBody),
            editedAt: Value(PgDateTime(DateTime.timestamp())),
            mentions: Value(mentions),
          ),
        );
  }

  Future<void> deleteRoomMessage({required String messageId}) =>
      _db.managers.beaconRoomMessages
          .filter((m) => m.id.equals(messageId))
          .delete();

  Future<BeaconParticipant?> findParticipant({
    required String beaconId,
    required String userId,
  }) =>
      _db.managers.beaconParticipants
          .filter((r) => r.beaconId.id(beaconId) & r.userId.id(userId))
          .getSingleOrNull();

  Future<List<BeaconParticipant>> listParticipants(String beaconId) =>
      _db.managers.beaconParticipants
          .filter((r) => r.beaconId.id(beaconId))
          .get();

  /// Active help offer `help_type` wire per user id for this beacon (at most one row per user).
  Future<Map<String, String?>> helpTypesByUserId(String beaconId) async {
    final rows = await _db.managers.beaconHelpOffers
        .filter((e) => e.beaconId.id(beaconId) & e.status.equals(0))
        .get();
    return {for (final r in rows) r.userId: r.helpType};
  }

  /// `user.displayName` for V2 row projections (missing users yield no map entry).
  /// Trims `user.handle` per id (empty string when unset).
  Future<Map<String, String>> userHandlesByIds(Iterable<String> userIds) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) {
      return {};
    }
    final users =
        await _db.managers.users.filter((u) => u.id.isIn(ids)).get();
    return {for (final u in users) u.id: (u.handle ?? '').trim()};
  }

  /// Resolves `@handle` tokens in [body] to admitted participant user ids
  /// (case-insensitive; duplicate handles → all matching user ids).
  Future<List<String>> resolveMentionUserIdsForBeacon({
    required String beaconId,
    required String body,
  }) async {
    final tokens = extractMentionHandleTokens(body);
    if (tokens.isEmpty) {
      return const [];
    }
    final participants = await listParticipants(beaconId);
    final admitted = participants
        .where((p) => p.roomAccess == RoomAccessBits.admitted)
        .toList();
    if (admitted.isEmpty) {
      return const [];
    }
    final handlesByUserId =
        await userHandlesByIds(admitted.map((p) => p.userId));
    final out = <String>[];
    for (final t in tokens) {
      for (final p in admitted) {
        final h = handlesByUserId[p.userId] ?? '';
        if (h.isEmpty) {
          continue;
        }
        if (h.toLowerCase() == t) {
          out.add(p.userId);
        }
      }
    }
    return out.toSet().toList();
  }

  Future<Map<String, String>> userTitlesByIds(Iterable<String> userIds) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) {
      return {};
    }
    final users = await _db.managers.users.filter((u) => u.id.isIn(ids)).get();
    return {for (final u in users) u.id: u.displayName};
  }

  Future<Map<String, ({
    bool hasPicture,
    int picHeight,
    int picWidth,
    String blurHash,
    String imageId,
  })>> userPicMetaByIds(Iterable<String> userIds) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) {
      return {};
    }

    final users = await _db.managers.users.filter((u) => u.id.isIn(ids)).get();
    if (users.isEmpty) {
      return {};
    }

    final imageUuidIds = {
      for (final u in users)
        if (u.imageId case final UuidValue id) id,
    }.toList();

    final imageByUuid = <UuidValue, Image>{};
    if (imageUuidIds.isNotEmpty) {
      final imgs =
          await _db.managers.images.filter((i) => i.id.isIn(imageUuidIds)).get();
      for (final img in imgs) {
        imageByUuid[img.id] = img;
      }
    }

    final out = <String, ({
      bool hasPicture,
      int picHeight,
      int picWidth,
      String blurHash,
      String imageId,
    })>{};

    for (final u in users) {
      final imgUuid = u.imageId;
      final img = imgUuid != null ? imageByUuid[imgUuid] : null;
      out[u.id] = (
        hasPicture: imgUuid != null && img != null,
        picHeight: img?.height ?? 0,
        picWidth: img?.width ?? 0,
        blurHash: img?.hash ?? '',
        imageId: img?.id.toString() ?? '',
      );
    }
    return out;
  }

  Future<void> participantOfferHelp({
    required String beaconId,
    required String userId,
    required String note,
  }) =>
      _db.withMutatingUser(userId, () async {
        final existing = await findParticipant(
          beaconId: beaconId,
          userId: userId,
        );
        if (existing == null) {
          await _db.managers.beaconParticipants.create(
            (o) => o(
              createdAt: const Value.absent(),
              updatedAt: const Value.absent(),
              id: generateId('P'),
              beaconId: beaconId,
              userId: userId,
              role: BeaconParticipantRoleBits.helper,
              status: const Value(BeaconParticipantStatusBits.offeredHelp),
              roomAccess: const Value(RoomAccessBits.requested),
              offerNote: Value(note),
            ),
          );
        } else {
          await _db.managers.beaconParticipants
              .filter(
                (r) => r.beaconId.id(beaconId) & r.userId.id(userId),
              )
              .update(
                (o) => o(
                  status: const Value(BeaconParticipantStatusBits.offeredHelp),
                  roomAccess: const Value(RoomAccessBits.requested),
                  offerNote: Value(note),
                  updatedAt: Value(PgDateTime(DateTime.timestamp())),
                ),
              );
        }
      });

  Future<void> admitParticipant({
    required String beaconId,
    required String participantUserId,
    required String actorUserId,
  }) =>
      _db.withMutatingUser(actorUserId, () async {
        await _db.managers.beaconParticipants
            .filter(
              (r) => r.beaconId.id(beaconId) & r.userId.id(participantUserId),
            )
            .update(
              (o) => o(
                roomAccess:
                    const Value(RoomAccessBits.admitted),
                status: const Value(BeaconParticipantStatusBits.committed),
                updatedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
      });

  /// Author coordination: admit helper into beacon Room (creates participant row when absent).
  Future<void> inviteOfferUserToBeaconRoom({
    required String beaconId,
    required String offerUserId,
    required String authorUserId,
  }) async {
    await _db.withMutatingUser(authorUserId, () async {
      final existing = await findParticipant(
        beaconId: beaconId,
        userId: offerUserId,
      );
      if (existing == null) {
        await _db.managers.beaconParticipants.create(
          (o) => o(
            createdAt: const Value.absent(),
            updatedAt: const Value.absent(),
            id: generateId('P'),
            beaconId: beaconId,
            userId: offerUserId,
            role: BeaconParticipantRoleBits.helper,
            status: const Value(BeaconParticipantStatusBits.committed),
            roomAccess: const Value(RoomAccessBits.admitted),
          ),
        );
      } else {
        await _db.managers.beaconParticipants
            .filter(
              (r) => r.beaconId.id(beaconId) & r.userId.id(offerUserId),
            )
            .update(
              (o) => o(
                roomAccess: const Value(RoomAccessBits.admitted),
                status: const Value(BeaconParticipantStatusBits.committed),
                updatedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
      }
    });
  }

  /// Author coordination: revoke Room access for this helper (`room_access = none`).
  Future<void> revokeOfferUserBeaconRoomAccess({
    required String beaconId,
    required String offerUserId,
    required String authorUserId,
  }) async {
    await _db.withMutatingUser(authorUserId, () async {
      final existing = await findParticipant(
        beaconId: beaconId,
        userId: offerUserId,
      );
      if (existing == null) {
        return;
      }
      await _db.managers.beaconParticipants
          .filter(
            (r) => r.beaconId.id(beaconId) & r.userId.id(offerUserId),
          )
          .update(
            (o) => o(
              roomAccess: const Value(RoomAccessBits.none),
              updatedAt: Value(PgDateTime(DateTime.timestamp())),
            ),
          );
    });
  }

  Future<void> setBeaconSteward({
    required String beaconId,
    required String stewardUserId,
    required String authorUserId,
  }) =>
      _db.withMutatingUser(authorUserId, () async {
        await _db.into(_db.beaconStewards).insertOnConflictUpdate(
              BeaconStewardsCompanion.insert(
                beaconId: beaconId,
                userId: stewardUserId,
              ),
            );
        await _db.managers.beaconParticipants
            .filter(
              (r) => r.beaconId.id(beaconId) & r.userId.id(stewardUserId),
            )
            .update(
              (o) => o(
                role: const Value(BeaconParticipantRoleBits.steward),
                updatedAt: Value(PgDateTime(DateTime.timestamp())),
              ),
            );
      });

  Future<void> toggleReaction({
    required String messageId,
    required String userId,
    required String emoji,
  }) =>
      _db.withMutatingUser(userId, () async {
        final existing = await _db.managers.beaconRoomMessageReactions
            .filter(
              (r) =>
                  r.messageId.id(messageId) &
                  r.userId.id(userId) &
                  r.emoji.equals(emoji),
            )
            .getSingleOrNull();
        if (existing != null) {
          await _db.managers.beaconRoomMessageReactions
              .filter((r) => r.id.equals(existing.id))
              .delete();
        } else {
          await _db.managers.beaconRoomMessageReactions.create(
            (o) => o(
              id: generateId('E'),
              messageId: messageId,
              userId: userId,
              emoji: emoji,
              createdAt: const Value.absent(),
            ),
          );
        }
      });

  Future<bool> isBeaconAuthor({
    required String beaconId,
    required String userId,
  }) async {
    final b = await _db.managers.beacons
        .filter((e) => e.id.equals(beaconId))
        .getSingleOrNull();
    return b?.userId == userId;
  }

  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) =>
      _db.managers.beaconStewards
          .filter(
            (s) => s.beaconId.id(beaconId) & s.userId.id(userId),
          )
          .getSingleOrNull()
          .then((r) => r != null);

  Future<BeaconRoomState?> getBeaconRoomState(String beaconId) =>
      _db.managers.beaconRoomStates
          .filter((e) => e.beaconId.id(beaconId))
          .getSingleOrNull();

  Future<void> markBeaconRoomSeen({
    required String userId,
    required String beaconId,
    required String? threadItemId,
    required DateTime at,
  }) =>
      _db.withMutatingUser(userId, () async {
        // customStatement accepts strings/nums only — bind timestamptz as ISO text.
        final seenAtIso = at.toUtc().toIso8601String();
        if (threadItemId == null) {
          await _db.customStatement(
            r'INSERT INTO beacon_room_seen (user_id, beacon_id, thread_item_id, last_seen_at) '
            r'VALUES ($1, $2, NULL, $3::timestamptz) '
            r'ON CONFLICT (user_id, beacon_id) WHERE thread_item_id IS NULL '
            r'DO UPDATE SET last_seen_at = EXCLUDED.last_seen_at',
            [userId, beaconId, seenAtIso],
          );
        } else {
          await _db.customStatement(
            r'INSERT INTO beacon_room_seen (user_id, beacon_id, thread_item_id, last_seen_at) '
            r'VALUES ($1, $2, $3, $4::timestamptz) '
            r'ON CONFLICT (user_id, beacon_id, thread_item_id) WHERE thread_item_id IS NOT NULL '
            r'DO UPDATE SET last_seen_at = EXCLUDED.last_seen_at',
            [userId, beaconId, threadItemId, seenAtIso],
          );
        }
      });

  /// Newest main-room message timestamp, or null when the room has no messages.
  Future<DateTime?> latestMainRoomMessageCreatedAt(String beaconId) async {
    final row = await (_db.select(_db.beaconRoomMessages)
          ..where(
            (m) => m.beaconId.equals(beaconId) & m.threadItemId.isNull(),
          )
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.createdAt,
              mode: OrderingMode.desc,
            ),
          ])
          ..limit(1))
        .getSingleOrNull();
    return row?.createdAt.dateTime;
  }

  Future<DateTime?> getMainRoomLastSeen({
    required String beaconId,
    required String userId,
  }) async {
    final map = await mainRoomLastSeenByUserIds(
      beaconId: beaconId,
      userIds: [userId],
    );
    return map[userId];
  }

  Future<Map<String, DateTime>> mainRoomLastSeenByUserIds({
    required String beaconId,
    required List<String> userIds,
  }) async {
    if (userIds.isEmpty) {
      return const {};
    }
    final rows = await (_db.select(_db.beaconRoomSeen)
          ..where(
            (s) =>
                s.beaconId.equals(beaconId) &
                s.userId.isIn(userIds) &
                s.threadItemId.isNull(),
          ))
        .get();
    return {
      for (final row in rows) row.userId: row.lastSeenAt.dateTime,
    };
  }

  Future<void> markParticipantRoomSeen({
    required String beaconId,
    required String userId,
  }) =>
      markBeaconRoomSeen(
        userId: userId,
        beaconId: beaconId,
        threadItemId: null,
        at: DateTime.timestamp(),
      );

  Future<BeaconRoomMessage?> getRoomMessageById(String messageId) =>
      _db.managers.beaconRoomMessages
          .filter((m) => m.id.equals(messageId))
          .getSingleOrNull();

  Future<void> markRoomMessageSemanticDone({
    required String messageId,
    required String actingUserId,
  }) =>
      _db.withMutatingUser(actingUserId, () async {
        await _db.managers.beaconRoomMessages
            .filter((m) => m.id.equals(messageId))
            .update(
              (u) => u(
                semanticMarker: const Value(BeaconRoomSemanticMarker.done),
                systemPayload: Value(<String, Object?>{
                  'semanticActorId': actingUserId,
                }),
              ),
            );
      });

  /// Audit row for the Activity tab / timeline (Phase 5).
  Future<void> insertActivityEvent({
    required String beaconId,
    required int visibility,
    required int type,
    required String actorId,
    String? targetUserId,
    String? sourceMessageId,
    Map<String, Object?>? diff,
  }) =>
      _db.withMutatingUser(actorId, () async {
        await _db.managers.beaconActivityEvents.create(
          (o) => o(
            id: Value(BeaconActivityEventEntity.newId),
            beaconId: beaconId,
            visibility: visibility,
            type: type,
            actorId: Value(actorId),
            targetUserId: Value(targetUserId),
            sourceMessageId: Value(sourceMessageId),
            diff: Value(diff),
            createdAt: const Value.absent(),
          ),
        );
      });

  Future<List<Map<String, Object?>>> listActivityEvents({
    required String beaconId,
    int limit = 200,
  }) async {
    final rows = await (_db.select(_db.beaconActivityEvents)
          ..where((e) => e.beaconId.equals(beaconId))
          ..orderBy([
            (e) =>
                OrderingTerm(expression: e.createdAt, mode: OrderingMode.desc),
          ])
          ..limit(limit))
        .get();
    return rows
        .map(
          (r) => <String, Object?>{
            'id': r.id,
            'beaconId': r.beaconId,
            'visibility': r.visibility,
            'type': r.type,
            'actorId': r.actorId,
            'targetUserId': r.targetUserId,
            'sourceMessageId': r.sourceMessageId,
            'coordinationItemId': r.coordinationItemId,
            'diffJson': r.diff == null ? null : jsonEncode(r.diff),
            'createdAt': r.createdAt.dateTime.toUtc().toIso8601String(),
          },
        )
        .toList();
  }

  Future<String?> beaconAuthorUserId(String beaconId) async {
    final b =
        await _db.managers.beacons
            .filter((e) => e.id.equals(beaconId))
            .getSingleOrNull();
    return b?.userId;
  }

  Future<List<String>> listStewardUserIds(String beaconId) async {
    final rows = await _db.managers.beaconStewards
        .filter((s) => s.beaconId.id(beaconId))
        .get();
    return rows.map((r) => r.userId).toList();
  }

  Future<List<String>> listAdmittedUserIds(String beaconId) async {
    final rows = await listParticipants(beaconId);
    return rows
        .where((p) => p.roomAccess == RoomAccessBits.admitted)
        .map((p) => p.userId)
        .toList();
  }

  Future<List<String>> listAllParticipantUserIds(String beaconId) async {
    final rows = await listParticipants(beaconId);
    return rows.map((p) => p.userId).toSet().toList();
  }

  Future<String?> participantUserIdForRow(String participantRowId) async {
    final p = await _db.managers.beaconParticipants
        .filter((r) => r.id.equals(participantRowId))
        .getSingleOrNull();
    return p?.userId;
  }

  /// Room messages created strictly after [after] (exclusive), for unread counts.
  ///
  /// When [excludeAuthorId] is non-empty, messages authored by that user are omitted
  /// (your own messages are never "unread" for you).
  Future<int> countRoomMessagesAfter({
    required String beaconId,
    DateTime? after,
    String? excludeAuthorId,
  }) async {
    final exclude = excludeAuthorId?.trim();
    final excludeSelf = exclude != null && exclude.isNotEmpty;

    if (after == null) {
      final rows = await (_db.select(_db.beaconRoomMessages)
            ..where((m) {
              var cond =
                  m.beaconId.equals(beaconId) & m.threadItemId.isNull();
              if (excludeSelf) {
                // Postgres rejects Drift's `IS NOT $n` from [isNotValue]; use NOT (=).
                cond = cond & m.authorId.equals(exclude).not();
              }
              return cond;
            }))
          .get();
      return rows.length;
    }
    final rows = await (_db.select(_db.beaconRoomMessages)
          ..where((m) {
            var cond = m.beaconId.equals(beaconId) &
                m.threadItemId.isNull() &
                m.createdAt.isBiggerThanValue(PgDateTime(after));
            if (excludeSelf) {
              // Postgres rejects Drift's `IS NOT $n` from [isNotValue]; use NOT (=).
              cond = cond & m.authorId.equals(exclude).not();
            }
            return cond;
          }))
        .get();
    return rows.length;
  }

  Future<int> countAttachmentsForMessage(String messageId) async {
    final rows = await (_db.select(_db.beaconRoomMessageAttachments)
          ..where((a) => a.messageId.equals(messageId)))
        .get();
    return rows.length;
  }

  Future<BeaconRoomMessageAttachment?> getRoomMessageAttachmentById(
    String attachmentId,
  ) =>
      (_db.select(_db.beaconRoomMessageAttachments)
            ..where((a) => a.id.equals(attachmentId)))
          .getSingleOrNull();

  Future<void> insertRoomMessageAttachmentImage({
    required String attachmentId,
    required String messageId,
    required int position,
    required String imageId,
    required String mime,
    required int sizeBytes,
    required String displayName,
    required String mutatingUserId,
  }) =>
      _db.withMutatingUser(mutatingUserId, () async {
        await _db.into(_db.beaconRoomMessageAttachments).insert(
              BeaconRoomMessageAttachmentsCompanion.insert(
                id: attachmentId,
                messageId: messageId,
                kind: BeaconRoomMessageAttachmentKind.image,
                imageId: Value(UuidValue.fromString(imageId)),
                fileName: Value(displayName),
                mime: Value(mime),
                sizeBytes: Value(sizeBytes),
                position: Value(position),
              ),
            );
      });

  Future<void> insertRoomMessageAttachmentFile({
    required String attachmentId,
    required String messageId,
    required int position,
    required String storagePath,
    required String mime,
    required int sizeBytes,
    required String displayName,
    required String mutatingUserId,
  }) =>
      _db.withMutatingUser(mutatingUserId, () async {
        await _db.into(_db.beaconRoomMessageAttachments).insert(
              BeaconRoomMessageAttachmentsCompanion.insert(
                id: attachmentId,
                messageId: messageId,
                kind: BeaconRoomMessageAttachmentKind.file,
                fileUrl: Value(storagePath),
                fileName: Value(displayName),
                mime: Value(mime),
                sizeBytes: Value(sizeBytes),
                position: Value(position),
              ),
            );
      });
}
