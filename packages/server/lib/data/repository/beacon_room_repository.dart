import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/app/sentry/sentry_db_span.dart';
import 'package:tentura_server/consts/beacon_participant_status_bits.dart';
import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_record.dart';
import 'package:tentura_server/utils/room_mention_utils.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_entity.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/entity/room_read_watermark_record.dart';
import 'package:tentura_server/domain/entity/room_latest_activity.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/util/room_reply_excerpt.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart';
import 'beacon_room_participant_join_recorder.dart';
import 'mappers/coordination_row_mappers.dart';
import 'offer_accepted_dismissal_repository.dart';

/// Beacon Room messages + participants — Postgres via Drift.
@LazySingleton(as: BeaconRoomRepositoryPort)
class BeaconRoomRepository implements BeaconRoomRepositoryPort {
  const BeaconRoomRepository(this._db);

  final TenturaDb _db;

  /// Of [peerIds], those with a block either way with [viewerUserId].
  Future<Set<String>> _blockHiddenPeers({
    required String viewerUserId,
    required Set<String> peerIds,
  }) async {
    if (peerIds.isEmpty) return const {};
    final rows = await _db
        .customSelect(
          r'SELECT peer FROM unnest($2::text[]) AS peer '
          r'WHERE public.block_hides($1, peer)',
          variables: [
            Variable<String>(viewerUserId),
            Variable<List<String>>(peerIds.toList(), PgTypes.textArray),
          ],
        )
        .get();
    return {for (final r in rows) r.read<String>('peer')};
  }

  // DORMANT(item-threads): thread_item_id message filter (non-null selects item thread).
  // Rooms are General-only (guard: beacon_room_message_general_only_guard, DiscussionScopeDisabledException); thread_item_id is always NULL for new rows. Do not design for this path. See #192.
  Future<List<BeaconRoomMessage>> listMessages({
    required String beaconId,
    String? threadItemId,
    DateTime? before,
    String? messageId,
    int limit = 50,
    String? hideBlockedAuthorsFor,
  }) async {
    Expression<bool> threadFilter($BeaconRoomMessagesTable m) {
      final tid = threadItemId;
      if (tid == null) {
        return m.threadItemId.isNull();
      }
      return m.threadItemId.equals(tid);
    }

    Expression<bool> messageFilter($BeaconRoomMessagesTable m) =>
        messageId == null ? const Constant(true) : m.id.equals(messageId);

    // Request Questions: its audience is wider than one room, so a message
    // is hidden from a viewer when its author and the viewer blocked each
    // other (either way), the same wall as `block_hides`.
    Expression<bool> blockFilter($BeaconRoomMessagesTable m) {
      final viewer = hideBlockedAuthorsFor;
      if (viewer == null) return const Constant(true);
      final ub = _db.userBlocks;
      return m.authorId.isNull() |
          notExistsQuery(
            _db.selectOnly(ub)
              ..addColumns([ub.blockerId])
              ..where(
                (ub.blockerId.equals(viewer) &
                        ub.blockedId.equalsExp(m.authorId)) |
                    (ub.blockedId.equals(viewer) &
                        ub.blockerId.equalsExp(m.authorId)),
              ),
          );
    }

    if (before == null) {
      return (_db.select(_db.beaconRoomMessages)
            ..where(
              (m) =>
                  m.beaconId.equals(beaconId) &
                  threadFilter(m) &
                  messageFilter(m) &
                  blockFilter(m),
            )
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
          ..where(
            (m) =>
                m.beaconId.equals(beaconId) &
                threadFilter(m) &
                messageFilter(m) &
                blockFilter(m) &
                m.createdAt.isSmallerThanValue(PgDateTime(before)),
          )
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

    final attachmentRows =
        await (_db.select(_db.beaconRoomMessageAttachments)
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
      final aimgs = await _db.managers.images
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

  Future<Set<String>> _messageIdsWithAttachments(List<String> ids) async {
    final filtered = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (filtered.isEmpty) {
      return {};
    }
    final rows = await (_db.select(
      _db.beaconRoomMessageAttachments,
    )..where((a) => a.messageId.isIn(filtered))).get();
    return {for (final row in rows) row.messageId};
  }

  /// Room messages with author profile projection + reaction aggregates for V2
  /// `RoomMessageList`.
  ///
  /// Uses drift `listMessages` for ordering/filter (same SQL path as before beacon
  /// room enrichment). Raw SQL with `ORDER BY`/`LIMIT` + drift placeholders hit a
  /// Postgres parser issue (`syntax error at or near "ORDER"`).
  // DORMANT(item-threads): thread-scoped reply-parent lookup filter; always null in production (General is thread_item_id IS NULL).
  // Rooms are General-only (guard: beacon_room_message_general_only_guard, DiscussionScopeDisabledException); thread_item_id is always NULL for new rows. Do not design for this path. See #192.
  Future<List<Map<String, Object?>>> listMessagesEnriched({
    required String beaconId,
    required String viewerUserId,
    String? threadItemId,
    DateTime? before,
    String? messageId,
    int limit = 50,
  }) async {
    final msgs = await listMessages(
      beaconId: beaconId,
      threadItemId: threadItemId,
      before: before,
      messageId: messageId,
      limit: limit,
      // The only live thread scope is Request Questions, whose audience
      // crosses blocks: hide authors blocked either way from the viewer.
      hideBlockedAuthorsFor: threadItemId == null ? null : viewerUserId,
    );
    if (msgs.isEmpty) {
      return [];
    }

    // Plan §8.4: one batch for the page's quoted revision snapshots, before
    // the author / attachment batches so pinner ids and fact source message
    // ids fold into them. No statement when nothing on the page quotes.
    final quotedMsgs = [
      for (final m in msgs)
        if (m.quotedFactCardId != null && m.quotedFactRevisionSeq != null) m,
    ];
    final quoteRowByKey = <String, QueryRow>{};
    if (quotedMsgs.isNotEmpty) {
      final quoteRows = await sentryDbSpan(
        'db.quote.batch',
        (_) => _db
            .customSelect(
              r'''
SELECT
  q.fact_card_id, q.seq, r.fact_text,
  f.pinned_by, f.source_message_id,
  f.visibility::integer AS visibility, f.status::integer AS status,
  f.revision_seq::integer AS current_seq,
  COALESCE(r.attachments_json::text, '[]') AS attachments_json
FROM unnest($1::text[], $2::integer[]) AS q(fact_card_id, seq)
JOIN public.beacon_fact_card f ON f.id = q.fact_card_id
JOIN public.beacon_fact_card_revision r
  ON r.fact_card_id = q.fact_card_id AND r.seq = q.seq
''',
              variables: [
                Variable(
                  TypedValue(Type.textArray, [
                    for (final m in quotedMsgs) m.quotedFactCardId!,
                  ]),
                ),
                Variable(
                  TypedValue(Type.integerArray, [
                    for (final m in quotedMsgs) m.quotedFactRevisionSeq!,
                  ]),
                ),
              ],
            )
            .get(),
      );
      for (final row in quoteRows) {
        quoteRowByKey['${row.read<String>('fact_card_id')}#'
                '${row.read<int>('seq')}'] =
            row;
      }
    }

    final authorIds = {
      ...msgs.map((m) => m.authorId).whereType<String>(),
      for (final row in quoteRowByKey.values)
        if (row.readNullable<String>('pinned_by') case final String id) id,
    }.toList();
    final users = await _db.managers.users
        .filter((u) => u.id.isIn(authorIds))
        .get();
    final userById = {for (final u in users) u.id: u};

    final ids = msgs.map((m) => m.id).toList();
    final reactionRows = await (_db.select(
      _db.beaconRoomMessageReactions,
    )..where((r) => r.messageId.isIn(ids))).get();

    final reactorIds = reactionRows.map((r) => r.userId).toSet();
    final missingReactorUserIds = reactorIds
        .difference(userById.keys.toSet())
        .toList();
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
      final imgs = await _db.managers.images
          .filter((i) => i.id.isIn(imageUuidIds))
          .get();
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

      final byEmoji = reactorsByMessage.putIfAbsent(
        mid,
        () => <String, List<Map<String, Object?>>>{},
      );
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

    final attachmentsJsonByMid = await attachmentsJsonByMessageIds([
      ...ids,
    ]);

    Map<String, Object?>? quotedFactFor(BeaconRoomMessage m) {
      final row =
          quoteRowByKey['${m.quotedFactCardId}#${m.quotedFactRevisionSeq}'];
      if (row == null) {
        return null;
      }
      final pinnedById = row.readNullable<String>('pinned_by');
      return <String, Object?>{
        'factCardId': row.read<String>('fact_card_id'),
        'seq': row.read<int>('seq'),
        'text': row.read<String>('fact_text'),
        'pinnedById': pinnedById,
        'pinnedByTitle': pinnedById != null
            ? (userById[pinnedById]?.displayName ?? '')
            : '',
        'visibility': row.read<int>('visibility'),
        'status': row.read<int>('status'),
        'currentSeq': row.read<int>('current_seq'),
        'attachmentsJson': row.read<String>('attachments_json'),
      };
    }

    final pollDataJsonByMid = await _pollDataJsonByMessageIds(
      msgs: msgs,
      viewerUserId: viewerUserId,
    );

    final batonDataJsonByMid = await _batonDataJsonByMessageIds(
      messageIds: ids,
      viewerUserId: viewerUserId,
    );

    final linkedItemIds = <String>{
      for (final m in msgs)
        if ((m.linkedItemId ?? '').isNotEmpty) m.linkedItemId!,
    }.toList();

    final linkedCoordinationItemById = <String, CoordinationItem>{};
    if (linkedItemIds.isNotEmpty) {
      final itemRows = await (_db.select(
        _db.coordinationItems,
      )..where((t) => t.id.isIn(linkedItemIds))).get();
      for (final row in itemRows) {
        linkedCoordinationItemById[row.id] = row;
      }
    }

    final parentIds = {
      for (final m in msgs)
        if ((m.replyToMessageId ?? '').isNotEmpty) m.replyToMessageId!,
    }.toList();
    final parentById = <String, BeaconRoomMessage>{};
    if (parentIds.isNotEmpty) {
      Expression<bool> parentThreadFilter($BeaconRoomMessagesTable t) {
        final tid = threadItemId;
        if (tid == null) {
          return t.threadItemId.isNull();
        }
        return t.threadItemId.equals(tid);
      }

      final parents =
          await (_db.select(_db.beaconRoomMessages)..where(
                (t) =>
                    t.id.isIn(parentIds) &
                    t.beaconId.equals(beaconId) &
                    parentThreadFilter(t),
              ))
              .get();
      // Questions (the only live thread scope): a reply never quotes an
      // author the viewer is blocked with, either way.
      final hiddenParentAuthors = threadItemId == null
          ? const <String>{}
          : await _blockHiddenPeers(
              viewerUserId: viewerUserId,
              peerIds: {
                for (final p in parents)
                  if (p.authorId case final String id) id,
              },
            );
      for (final parent in parents) {
        if (hiddenParentAuthors.contains(parent.authorId)) continue;
        parentById[parent.id] = parent;
      }
      final missingParentAuthorIds = parents
          .map((p) => p.authorId)
          .whereType<String>()
          .toSet()
          .difference(userById.keys.toSet())
          .toList();
      if (missingParentAuthorIds.isNotEmpty) {
        final parentAuthors = await _db.managers.users
            .filter((u) => u.id.isIn(missingParentAuthorIds))
            .get();
        for (final u in parentAuthors) {
          userById[u.id] = u;
        }
      }
    }
    final attachmentParentIds = parentIds.isEmpty
        ? <String>{}
        : await _messageIdsWithAttachments(parentIds);
    // A poll parent has no body; its quote is the poll question (#377).
    final parentPollingIds = {
      for (final p in parentById.values)
        if (p.linkedPollingId case final String id) id,
    };
    final parentPolls = parentPollingIds.isEmpty
        ? const <Polling>[]
        : await _db.managers.pollings
              .filter((p) => p.id.isIn(parentPollingIds))
              .get();
    final pollQuestionById = {for (final p in parentPolls) p.id: p.question};

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
      final linkedRow = linkedId != null
          ? linkedCoordinationItemById[linkedId]
          : null;
      final parent = m.replyToMessageId != null
          ? parentById[m.replyToMessageId]
          : null;

      return <String, Object?>{
        'id': id,
        'beaconId': m.beaconId,
        // Hierarchy notices are system-authored; preserve the non-null wire
        // contract without attributing them to a user.
        'authorId': m.authorId ?? '',
        'body': m.body,
        'createdAt': m.createdAt.dateTime.toUtc().toIso8601String(),
        'editedAt': m.editedAt?.dateTime.toUtc().toIso8601String(),
        'semanticMarker': m.semanticMarker,
        'systemMessageKind': m.systemMessageKind,
        'linkedBlockerId':
            linkedRow != null && linkedRow.kind == coordinationItemKindBlocker
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
          'linkedItemTargetPersonId': linkedRow.targetPersonId,
          'linkedItemCreatedAt': linkedRow.createdAt.dateTime
              .toUtc()
              .toIso8601String(),
          'linkedItemUpdatedAt': linkedRow.updatedAt.dateTime
              .toUtc()
              .toIso8601String(),
          'linkedItemLinkedMessageId': linkedRow.linkedMessageId,
          'linkedItemResolvedAt': linkedRow.resolvedAt?.dateTime
              .toUtc()
              .toIso8601String(),
        },
        'pollDataJson': pollDataJsonByMid[id],
        'batonDataJson': batonDataJsonByMid[id],
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
        'attachmentsJson': attachmentsJsonByMid[id] ?? '[]',
        'mentionSpansJson': jsonEncode(m.mentionSpans),
        // GraphQL `[String!]` — never emit null/empty slots (see migration 0060).
        'mentions': m.mentions.where((id) => id.isNotEmpty).toList(),
        'threadItemId': m.threadItemId,
        // A reply to a message hidden from this viewer (Questions blocks)
        // does not reveal the hidden message's id either.
        'replyToMessageId':
            m.replyToMessageId != null && threadItemId != null && parent == null
            ? null
            : m.replyToMessageId,
        'replyToAuthorId': parent?.authorId,
        'replyToAuthorTitle': parent != null && parent.authorId != null
            ? (userById[parent.authorId!]?.displayName ?? '')
            : null,
        'replyToBodyExcerpt': parent != null
            ? roomReplyExcerpt(
                parent.body,
                pollQuestion: pollQuestionById[parent.linkedPollingId],
              )
            : null,
        'replyToHasAttachments': parent != null
            ? attachmentParentIds.contains(parent.id)
            : null,
        'quotedFact': quotedFactFor(m),
      };
    }).toList();
  }

  @override
  Future<Map<String, Object?>?> roomMessageTarget({
    required String beaconId,
    required String messageId,
    required String viewerUserId,
  }) async {
    final message = await getRoomMessageById(messageId);
    if (message == null || message.beaconId != beaconId) {
      return null;
    }
    final rows = await listMessagesEnriched(
      beaconId: beaconId,
      viewerUserId: viewerUserId,
      threadItemId: message.threadItemId,
      messageId: messageId,
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  /// Per-viewer «Who'll take it?» payload (plan §1.4); absent key = `null`.
  Future<Map<String, String?>> _batonDataJsonByMessageIds({
    required List<String> messageIds,
    required String viewerUserId,
  }) async {
    if (messageIds.isEmpty) return {};
    final batonRows = await _db
        .customSelect(
          r'''
SELECT b.id, b.message_id, b.author_id, b.status::integer AS status,
       b.taker_id, b.selection_mode::integer AS selection_mode
FROM public.beacon_room_baton b
WHERE b.message_id = ANY($1::text[])
''',
          variables: [Variable(TypedValue(Type.textArray, messageIds))],
        )
        .get();
    if (batonRows.isEmpty) return {};

    final batonIds = [for (final r in batonRows) r.read<String>('id')];
    final candidateRows = await _db
        .customSelect(
          r'''
SELECT baton_id, user_id, tier::integer AS tier,
       response::integer AS response, responded_at
FROM public.beacon_room_baton_candidate
WHERE baton_id = ANY($1::text[])
ORDER BY tier, user_id
''',
          variables: [Variable(TypedValue(Type.textArray, batonIds))],
        )
        .get();
    final candidatesByBatonId = <String, List<QueryRow>>{};
    for (final r in candidateRows) {
      candidatesByBatonId
          .putIfAbsent(r.read<String>('baton_id'), () => [])
          .add(r);
    }

    final titleUserIds = <String>{
      for (final r in batonRows)
        if (r.readNullable<String>('taker_id') case final String id) id,
      for (final r in batonRows)
        if (r.read<String>('author_id') == viewerUserId)
          for (final c
              in candidatesByBatonId[r.read<String>('id')] ??
                  const <QueryRow>[])
            c.read<String>('user_id'),
    }.toList();
    final titleById = <String, String>{};
    if (titleUserIds.isNotEmpty) {
      final users = await _db.managers.users
          .filter((u) => u.id.isIn(titleUserIds))
          .get();
      for (final u in users) {
        titleById[u.id] = u.displayName;
      }
    }

    String? isoOrNull(QueryRow row, String column) {
      final v = row.data[column];
      if (v == null) return null;
      if (v is DateTime) return v.toUtc().toIso8601String();
      return DateTime.tryParse(v.toString())?.toUtc().toIso8601String();
    }

    String responseName(int v) => switch (v) {
      1 => 'can_help',
      2 => 'cant_help',
      _ => 'waiting',
    };

    final out = <String, String?>{};
    for (final b in batonRows) {
      final batonId = b.read<String>('id');
      final status = b.read<int>('status');
      final statusName = switch (status) {
        1 => 'taken',
        2 => 'cancelled',
        _ => 'collecting',
      };
      final takerId = b.readNullable<String>('taker_id');
      final taken = status == 1 && takerId != null;
      Map<String, Object?> taker() => {
        'id': takerId,
        'title': titleById[takerId] ?? '',
      };
      final candidates = candidatesByBatonId[batonId] ?? const <QueryRow>[];
      final Map<String, Object?> payload;

      if (b.read<String>('author_id') == viewerUserId) {
        payload = {
          'id': batonId,
          'status': statusName,
          'viewerRole': 'author',
          'candidates': [
            for (final c in candidates)
              {
                'userId': c.read<String>('user_id'),
                'title': titleById[c.read<String>('user_id')] ?? '',
                'tier': c.read<int>('tier'),
                'response': responseName(c.read<int>('response')),
                'respondedAt': isoOrNull(c, 'responded_at'),
              },
          ],
          'allAnswered': candidates.every(
            (c) => c.read<int>('response') != 0,
          ),
          'eligibleCount': candidates
              .where((c) => c.read<int>('response') == 1)
              .length,
          if (taken) ...{
            'taker': taker(),
            'selectionMode': b.readNullable<int>('selection_mode') == 2
                ? 'manual'
                : 'auto',
          },
        };
      } else {
        QueryRow? mine;
        for (final c in candidates) {
          if (c.read<String>('user_id') == viewerUserId) mine = c;
        }
        if (mine != null) {
          final myResponse = mine.read<int>('response');
          final outcome = status == 0
              ? null
              : takerId == viewerUserId
              ? 'you'
              : status == 1 && myResponse == 1
              ? 'someoneElse'
              : 'closed';
          payload = {
            'id': batonId,
            'status': statusName,
            'viewerRole': 'candidate',
            if (status != 2) 'myResponse': responseName(myResponse),
            'outcome': ?outcome,
            if (outcome == 'you') 'taker': taker(),
          };
        } else {
          // The baton is its own message, so the room sees that it exists;
          // who was asked and how they answered stays private (plan §1.4).
          payload = {
            'id': batonId,
            'status': statusName,
            'viewerRole': 'observer',
            if (taken) 'taker': taker(),
          };
        }
      }
      out[b.read<String>('message_id')] = jsonEncode(payload);
    }
    return out;
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

    final acts = await (_db.select(
      _db.pollingActs,
    )..where((a) => a.pollingId.isIn(pollingIds))).get();

    // Viewer's voted variant IDs per poll (supports multiple/range)
    final myVariantIdsByPollingId = <String, List<String>>{};
    for (final a in acts) {
      if (a.authorId == viewerUserId) {
        myVariantIdsByPollingId
            .putIfAbsent(a.pollingId, () => [])
            .add(a.pollingVariantId);
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
      voterIdsByVariantId
          .putIfAbsent(a.pollingVariantId, () => [])
          .add(a.authorId);
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

  Future<BeaconRoomMessageRecord> insertRoomMessage({
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
    List<Map<String, Object?>> mentionSpans = const [],
    String? quotedFactCardId,
    int? quotedFactRevisionSeq,
    String? clientMessageId,
  }) => _db.withMutatingUser(authorId, () async {
    final id = generateId('R');
    try {
      return await _insertRoomMessage(
        id: id,
        beaconId: beaconId,
        authorId: authorId,
        body: body,
        replyToMessageId: replyToMessageId,
        threadItemId: threadItemId,
        linkedParticipantId: linkedParticipantId,
        linkedPollingId: linkedPollingId,
        semanticMarker: semanticMarker,
        systemPayload: systemPayload,
        mentions: mentions,
        mentionSpans: mentionSpans,
        quotedFactCardId: quotedFactCardId,
        quotedFactRevisionSeq: quotedFactRevisionSeq,
        clientMessageId: clientMessageId,
      );
    } on UniqueViolationException catch (error) {
      if (error.constraintName !=
          'beacon_room_message_author_client_message_id_key') {
        rethrow;
      }
      throw const RoomMessageClientIdTakenException();
    }
  });

  Future<BeaconRoomMessageRecord> _insertRoomMessage({
    required String id,
    required String beaconId,
    required String authorId,
    required String body,
    required String? replyToMessageId,
    required String? threadItemId,
    required String? linkedParticipantId,
    required String? linkedPollingId,
    required int? semanticMarker,
    required Map<String, Object?>? systemPayload,
    required List<String> mentions,
    required List<Map<String, Object?>> mentionSpans,
    required String? quotedFactCardId,
    required int? quotedFactRevisionSeq,
    required String? clientMessageId,
  }) async {
    if (quotedFactCardId != null || quotedFactRevisionSeq != null) {
      // Plan §8.5: one insert-select; yields a row only for a live fact of the
      // same beacon with an existing revision seq, in the General scope.
      final rows = await _db
          .customSelect(
            '''
INSERT INTO public.beacon_room_message
  (id, beacon_id, author_id, body, reply_to_message_id, thread_item_id,
   linked_next_move_id, linked_polling_id, semantic_marker, system_payload,
   mentions, mention_spans, quoted_fact_card_id, quoted_fact_revision_seq,
   client_message_id, created_at)
SELECT \$1::text, \$2::text, \$3::text, \$4::text, \$5::text, \$6::text,
       \$7::text, \$8::text, \$9::smallint, \$10::jsonb, \$11::text[],
       \$12::jsonb, r.fact_card_id, r.seq, \$15::text, now()
FROM public.beacon_fact_card f
JOIN public.beacon_fact_card_revision r
  ON r.fact_card_id = f.id AND r.seq = \$14::integer
WHERE f.id = \$13::text
  AND f.beacon_id = \$2::text
  AND f.status <> ${BeaconFactCardStatusBits.removed}
  AND \$6::text IS NULL
RETURNING *
''',
            variables: [
              Variable<String>(id),
              Variable<String>(beaconId),
              Variable<String>(authorId),
              Variable<String>(body),
              Variable<String>(replyToMessageId),
              Variable<String>(threadItemId),
              Variable<String>(linkedParticipantId),
              Variable<String>(linkedPollingId),
              Variable<int>(semanticMarker),
              Variable<String>(
                systemPayload == null ? null : jsonEncode(systemPayload),
              ),
              Variable(TypedValue(Type.textArray, mentions)),
              Variable<String>(jsonEncode(mentionSpans)),
              Variable<String>(quotedFactCardId),
              Variable<int>(quotedFactRevisionSeq),
              Variable<String>(clientMessageId),
            ],
          )
          .get();
      if (rows.isEmpty) {
        throw IdWrongException(
          description:
              'Quoted fact [$quotedFactCardId] revision '
              '[$quotedFactRevisionSeq]',
        );
      }
      return _db.beaconRoomMessages.map(rows.single.data).toRecord();
    }
    return (await _db.managers.beaconRoomMessages.createReturning(
      (o) => o(
        id: id,
        beaconId: beaconId,
        authorId: Value(authorId),
        body: Value(body),
        replyToMessageId: Value(replyToMessageId),
        threadItemId: Value(threadItemId),
        linkedNextMoveId: Value(linkedParticipantId),
        linkedFactCardId: const Value.absent(),
        linkedPollingId: Value(linkedPollingId),
        semanticMarker: Value(semanticMarker),
        systemPayload: Value(systemPayload),
        mentions: Value(mentions),
        mentionSpans: Value(mentionSpans),
        clientMessageId: Value(clientMessageId),
        createdAt: const Value.absent(),
      ),
    )).toRecord();
  }

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
  }) => _db.withMutatingUser(actorUserId, () async {
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
    required List<Map<String, Object?>> mentionSpans,
  }) async {
    await _db.managers.beaconRoomMessages
        .filter((m) => m.id.equals(messageId))
        .update(
          (o) => o(
            body: Value(newBody),
            editedAt: Value(PgDateTime(DateTime.timestamp())),
            mentions: Value(mentions),
            mentionSpans: Value(mentionSpans),
          ),
        );
  }

  Future<void> deleteRoomMessage({required String messageId}) => _db
      .managers
      .beaconRoomMessages
      .filter((m) => m.id.equals(messageId))
      .delete();

  Future<BeaconParticipantRecord?> findParticipant({
    required String beaconId,
    required String userId,
  }) async =>
      (await _db.managers.beaconParticipants
              .filter((r) => r.beaconId.id(beaconId) & r.userId.id(userId))
              .getSingleOrNull())
          ?.toRecord();

  Future<List<BeaconParticipantRecord>> listParticipants(
    String beaconId,
  ) async {
    final rows = await _db.managers.beaconParticipants
        .filter((r) => r.beaconId.id(beaconId))
        .get();
    return rows.map((r) => r.toRecord()).toList();
  }

  @override
  Future<List<AdmittedRoomMentionParticipant>> listAdmittedMentionParticipants(
    String beaconId,
  ) async {
    final admitted = (await listParticipants(
      beaconId,
    )).where((p) => p.roomAccess == RoomAccessBits.admitted).toList();
    if (admitted.isEmpty) return const [];
    final ids = admitted.map((p) => p.userId);
    final titles = await userTitlesByIds(ids);
    final handles = await userHandlesByIds(ids);
    return [
      for (final p in admitted)
        AdmittedRoomMentionParticipant(
          userId: p.userId,
          displayName: titles[p.userId] ?? '',
          handle: handles[p.userId] ?? '',
        ),
    ];
  }

  /// Active help offer `help_type` wire per user id for this beacon (at most one row per user).
  Future<Map<String, String?>> helpTypesByUserId(String beaconId) async {
    final hints = await activeHelpOfferHintsByUserId(beaconId);
    return {for (final e in hints.entries) e.key: e.value.helpType};
  }

  /// Active help-offer fields per user. Key present ⇒ active offer.
  Future<Map<String, ({String? helpType, String roleLabel})>>
  activeHelpOfferHintsByUserId(String beaconId) async {
    final rows = await _db.managers.beaconHelpOffers
        .filter((e) => e.beaconId.id(beaconId) & e.status.equals(0))
        .get();
    return {
      for (final r in rows)
        r.userId: (helpType: r.helpType, roleLabel: r.roleLabel ?? ''),
    };
  }

  /// `user.displayName` for V2 row projections (missing users yield no map entry).
  /// Trims `user.handle` per id (empty string when unset).
  Future<Map<String, String>> userHandlesByIds(Iterable<String> userIds) async {
    final ids = userIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) {
      return {};
    }
    final users = await _db.managers.users.filter((u) => u.id.isIn(ids)).get();
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
    final admitted = await listAdmittedMentionParticipants(beaconId);
    if (admitted.isEmpty) {
      return const [];
    }
    final out = <String>[];
    for (final t in tokens) {
      for (final p in admitted) {
        final h = p.handle;
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

  Future<
    Map<
      String,
      ({
        bool hasPicture,
        int picHeight,
        int picWidth,
        String blurHash,
        String imageId,
      })
    >
  >
  userPicMetaByIds(Iterable<String> userIds) async {
    final profiles = await userProfilesByIds(userIds);
    return {
      for (final e in profiles.entries)
        e.key: (
          hasPicture: e.value.hasPicture,
          picHeight: e.value.picHeight,
          picWidth: e.value.picWidth,
          blurHash: e.value.blurHash,
          imageId: e.value.imageId,
        ),
    };
  }

  /// Title, handle and picture meta per user id from a single `user` read
  /// (plus one `image` read when any user has a picture).
  @override
  Future<
    Map<
      String,
      ({
        String title,
        String handle,
        bool hasPicture,
        int picHeight,
        int picWidth,
        String blurHash,
        String imageId,
      })
    >
  >
  userProfilesByIds(Iterable<String> userIds) async {
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
      final imgs = await _db.managers.images
          .filter((i) => i.id.isIn(imageUuidIds))
          .get();
      for (final img in imgs) {
        imageByUuid[img.id] = img;
      }
    }

    return {
      for (final u in users)
        u.id: (
          title: u.displayName,
          handle: (u.handle ?? '').trim(),
          hasPicture: u.imageId != null && imageByUuid[u.imageId] != null,
          picHeight: imageByUuid[u.imageId]?.height ?? 0,
          picWidth: imageByUuid[u.imageId]?.width ?? 0,
          blurHash: imageByUuid[u.imageId]?.hash ?? '',
          imageId: imageByUuid[u.imageId]?.id.toString() ?? '',
        ),
    };
  }

  Future<void> participantOfferHelp({
    required String beaconId,
    required String userId,
    required String note,
  }) => _db.withMutatingUser(userId, () async {
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
              // An addressee of a converted Post stays admitted.
              roomAccess: existing.role == BeaconParticipantRoleBits.addressee
                  ? const Value.absent()
                  : const Value(RoomAccessBits.requested),
              offerNote: Value(note),
              updatedAt: Value(PgDateTime(DateTime.timestamp())),
            ),
          );
    }
  });

  /// Author coordination: admit helper into beacon Room (creates participant row when absent).
  ///
  /// [authorUserId] is the confirming author, recorded as the join actor. The
  /// write runs in a mutating unit for [mutatingUserId] (default:
  /// [authorUserId]); see [_admitOfferUserToBeaconRoom].
  @override
  Future<void> inviteOfferUserToBeaconRoom({
    required String beaconId,
    required String offerUserId,
    required String authorUserId,
    String admissionReason = BeaconRoomAdmissionReason.accept,
    int participantStatus = BeaconParticipantStatusBits.committed,
    String? mutatingUserId,
  }) => _db.withMutatingUser(
    mutatingUserId ?? authorUserId,
    () => _admitOfferUserToBeaconRoom(
      beaconId: beaconId,
      offerUserId: offerUserId,
      confirmingAuthorId: authorUserId,
      admissionReason: admissionReason,
      participantStatus: participantStatus,
    ),
  );

  /// Actor-explicit body of [inviteOfferUserToBeaconRoom] (Arch §5.3): admits
  /// [offerUserId] with [confirmingAuthorId] recorded as the join actor, in
  /// the caller's mutating unit. It opens no mutating unit of its own.
  Future<void> _admitOfferUserToBeaconRoom({
    required String beaconId,
    required String offerUserId,
    required String confirmingAuthorId,
    String admissionReason = BeaconRoomAdmissionReason.accept,
    int participantStatus = BeaconParticipantStatusBits.committed,
  }) async {
    final existing = await findParticipant(
      beaconId: beaconId,
      userId: offerUserId,
    );
    final isPostMember = existing?.role == BeaconParticipantRoleBits.addressee;
    final isAdmittedAddressee =
        existing?.roomAccess == RoomAccessBits.admitted &&
        existing?.role == BeaconParticipantRoleBits.addressee;
    if (existing?.roomAccess == RoomAccessBits.admitted &&
        !isAdmittedAddressee) {
      return;
    }
    if (existing == null) {
      await _db.managers.beaconParticipants.create(
        (o) => o(
          createdAt: const Value.absent(),
          updatedAt: const Value.absent(),
          id: generateId('P'),
          beaconId: beaconId,
          userId: offerUserId,
          role: BeaconParticipantRoleBits.helper,
          status: Value(participantStatus),
          roomAccess: const Value(RoomAccessBits.admitted),
        ),
      );
    } else {
      await _db.managers.beaconParticipants
          .filter((r) => r.beaconId.id(beaconId) & r.userId.id(offerUserId))
          .update(
            (o) => o(
              roomAccess: const Value(RoomAccessBits.admitted),
              status: Value(participantStatus),
              role:
                  isAdmittedAddressee ||
                      (isPostMember &&
                          participantStatus ==
                              BeaconParticipantStatusBits.admitted)
                  ? const Value(BeaconParticipantRoleBits.helper)
                  : const Value.absent(),
              updatedAt: Value(PgDateTime(DateTime.timestamp())),
            ),
          );
    }
    if (isAdmittedAddressee) {
      return;
    }
    await recordBeaconRoomParticipantJoined(
      db: _db,
      beaconId: beaconId,
      joinedUserId: offerUserId,
      actorUserId: confirmingAuthorId,
      admissionReason: admissionReason,
    );
  }

  /// Author coordination: revoke Room access for this helper (`room_access = none`).
  @override
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
      // An addressee of a converted Post keeps access (leaving is `postLeave`).
      if (existing == null ||
          existing.role == BeaconParticipantRoleBits.addressee) {
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
      await clearOfferAcceptedDismissal(
        _db,
        beaconId: beaconId,
        userId: offerUserId,
      );
    });
  }

  @override
  Future<void> recordParticipantLeft({
    required String beaconId,
    required String userId,
    required String withdrawReason,
    String note = '',
  }) => _db.withMutatingUser(userId, () async {
    final trimmedNote = note.trim();
    final line = await _db.managers.beaconRoomMessages.createReturning(
      (o) => o(
        id: generateId('R'),
        beaconId: beaconId,
        authorId: Value(userId),
        body: const Value(''),
        semanticMarker: const Value(BeaconRoomSemanticMarker.participantLeft),
        systemPayload: Value(<String, Object?>{
          'leftUserId': userId,
          'withdrawReason': withdrawReason,
          if (trimmedNote.isNotEmpty) 'note': trimmedNote,
        }),
        createdAt: const Value.absent(),
      ),
    );
    // Same pairing as a join: the activity log shows the leave, linked to
    // the chat line it came with.
    await _db.managers.beaconActivityEvents.create(
      (o) => o(
        id: Value(BeaconActivityEventEntity.newId),
        beaconId: beaconId,
        visibility: BeaconActivityEventVisibilityBits.room,
        type: BeaconActivityEventTypeBits.participantLeft,
        actorId: Value(userId),
        targetUserId: Value(userId),
        sourceMessageId: Value(line.id),
        diff: Value(<String, Object?>{
          'leftUserId': userId,
          'withdrawReason': withdrawReason,
        }),
        createdAt: const Value.absent(),
      ),
    );
  });

  @override
  Future<void> recordParticipantRemoved({
    required String beaconId,
    required String userId,
  }) {
    Future<void> body() async {
      await _db.managers.beaconRoomMessages.create(
        (o) => o(
          id: generateId('R'),
          beaconId: beaconId,
          // The line is about the removed helper, as a leave line is; who
          // removed them is not shown to the room (U41).
          authorId: Value(userId),
          body: const Value(''),
          semanticMarker: const Value(
            BeaconRoomSemanticMarker.participantRemoved,
          ),
          systemPayload: Value(<String, Object?>{'removedUserId': userId}),
          createdAt: const Value.absent(),
        ),
      );
    }

    // Runs inside the author's removal unit of work; the actor there is the
    // author, so no new actor scope is opened here.
    return _db.isInAmbientMutatingTransaction
        ? body()
        : _db.withMutatingSystem(body);
  }

  @override
  Future<String> lockCurrentLine(String beaconId) =>
      _db.withJoinedTransaction(() async {
        // A missing row is created first so that two first edits also
        // serialise on it; the caller's upsert overwrites it right after.
        await _db.customStatement(
          r'INSERT INTO public.beacon_room_state (beacon_id) VALUES ($1) '
          'ON CONFLICT (beacon_id) DO NOTHING',
          [beaconId],
        );
        final row = await _db
            .customSelect(
              'SELECT current_line FROM public.beacon_room_state '
              r'WHERE beacon_id = $1 FOR UPDATE',
              variables: [Variable<String>(beaconId)],
            )
            .getSingle();
        return row.read<String>('current_line');
      });

  @override
  Future<BeaconRoomStateRecord?> setBeaconRoomCurrentLine({
    required String beaconId,
    required String text,
    required String updatedBy,
    required int baseRevision,
  }) => _db.withMutatingUser(updatedBy, () async {
    // Compare-and-set on the revision the editor opened with (#517). The
    // row lock of ON CONFLICT serializes two saves from the same base: the
    // second re-checks the WHERE against the committed first one and writes
    // nothing. The m0258 trigger bumps the revision.
    final written = await _db
        .customSelect(
          r'''
INSERT INTO public.beacon_room_state AS s (
  beacon_id, current_line, updated_by, updated_at
) VALUES ($1, $2, $3, now())
ON CONFLICT (beacon_id) DO UPDATE
SET current_line = EXCLUDED.current_line,
    updated_by = EXCLUDED.updated_by,
    updated_at = EXCLUDED.updated_at
WHERE s.current_line_revision = $4
RETURNING s.beacon_id
''',
          variables: [
            Variable<String>(beaconId),
            Variable<String>(text),
            Variable<String>(updatedBy),
            Variable<int>(baseRevision),
          ],
        )
        .get();
    if (written.isEmpty) return null;
    // Plan-only edits have no coordination item change to invalidate NOW.
    // Publish the existing request refresh hint atomically with the write.
    // `room_state` tells open rooms this `beacon` hint moved the next step;
    // they skip their room-state read on any other request update (#654).
    await _db.customStatement(
      r'''
SELECT public.emit_realtime_entity_change(
  'beacon', $1, 'update', public.realtime_beacon_recipients($1),
  '{"room_state": true}'::jsonb
)
''',
      [beaconId],
    );
    return getBeaconRoomState(beaconId);
  });

  Future<void> setBeaconSteward({
    required String beaconId,
    required String stewardUserId,
    required String authorUserId,
  }) => _db.withMutatingUser(authorUserId, () async {
    await _db
        .into(_db.beaconStewards)
        .insertOnConflictUpdate(
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

  Future<bool> toggleReaction({
    required String messageId,
    required String userId,
    required String emoji,
  }) => _db.withMutatingUser(userId, () async {
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
      return false;
    }
    await _db.managers.beaconRoomMessageReactions.create(
      (o) => o(
        id: generateId('E'),
        messageId: messageId,
        userId: userId,
        emoji: emoji,
        createdAt: const Value.absent(),
      ),
    );
    return true;
  });

  Future<bool> claimPostFirstResponse({
    required String beaconId,
    required String userId,
    required int kind,
    required String sourceId,
  }) => _db.withMutatingUser(userId, () async {
    final rows = await _db
        .customSelect(
          r'SELECT public.post_claim_first_response($1, $2, $3::smallint, $4) AS won',
          variables: [
            Variable<String>(beaconId),
            Variable<String>(userId),
            Variable<int>(kind),
            Variable<String>(sourceId),
          ],
        )
        .get();
    return rows.single.read<bool>('won');
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

  @override
  Future<bool> isBeaconSteward({
    required String beaconId,
    required String userId,
  }) => _db.managers.beaconStewards
      .filter(
        (s) => s.beaconId.id(beaconId) & s.userId.id(userId),
      )
      .getSingleOrNull()
      .then((r) => r != null);

  Future<BeaconRoomStateRecord?> getBeaconRoomState(String beaconId) async =>
      (await _db.managers.beaconRoomStates
              .filter((e) => e.beaconId.id(beaconId))
              .getSingleOrNull())
          ?.toRecord();

  @override
  Future<Map<String, RoomLatestActivity>> latestRoomActivities(
    Iterable<String> beaconIds, {
    required String viewerUserId,
  }) async {
    final ids = beaconIds.where((id) => id.isNotEmpty).toSet().toList();
    if (ids.isEmpty) {
      return {};
    }
    // One round trip for the whole batch (#541 review): each correlated
    // subquery and the LATERAL pick are served by the
    // `(beacon_id, created_at DESC)` indexes on the message and event tables.
    final rows = await _db
        .customSelect(
          r'''
SELECT
  ids.beacon_id,
  GREATEST(
    (SELECT max(m.created_at) FROM public.beacon_room_message m
      WHERE m.beacon_id = ids.beacon_id AND m.thread_item_id IS NULL),
    (SELECT s.updated_at FROM public.beacon_room_state s
      WHERE s.beacon_id = ids.beacon_id),
    (SELECT max(e.created_at) FROM public.beacon_activity_event e
      WHERE e.beacon_id = ids.beacon_id),
    -- W5 (#525): a new help offer, for those who decide on offers (author
    -- or steward). A re-offer after withdrawing reuses the offer row, so the
    -- append-only `offered` commitment fact (kind 0) carries its time; the
    -- row's own `created_at` covers offers older than those facts. Served by
    -- `beacon_commitment_event_beacon_idx` and the help offer primary key.
    CASE WHEN EXISTS (SELECT 1 FROM public.beacon b
            WHERE b.id = ids.beacon_id AND b.user_id = $2)
          OR EXISTS (SELECT 1 FROM public.beacon_steward st
            WHERE st.beacon_id = ids.beacon_id AND st.user_id = $2)
      THEN GREATEST(
        (SELECT max(ce.created_at) FROM public.beacon_commitment_event ce
          WHERE ce.beacon_id = ids.beacon_id AND ce.kind = 0),
        (SELECT max(o.created_at) FROM public.beacon_help_offer o
          WHERE o.beacon_id = ids.beacon_id))
    END
  ) AS last_activity_at,
  lm.created_at AS last_message_at,
  -- The Requests card shows one clipped line; don't ship whole bodies.
  -- Collapse whitespace before the cut, so a body that is mostly blank lines
  -- still reaches the 160-rune clip (and its "…") when it was cut here.
  -- #609: a poll with no text previews as its question (kind stays 'poll').
  left(regexp_replace(btrim(CASE
      WHEN btrim(lm.body) = '' AND lm.linked_polling_id IS NOT NULL
        THEN coalesce((SELECT p.question FROM public.polling p
          WHERE p.id = lm.linked_polling_id), '')
      ELSE lm.body
    END), '\s+', ' ', 'g'), 200)
    AS last_message_body,
  lm.author_id AS last_message_author_id,
  u.display_name AS last_message_author_name,
  -- #498: a message with no text still previews as its kind.
  CASE
    WHEN lm.id IS NULL OR btrim(lm.body) <> '' THEN NULL
    WHEN lm.linked_polling_id IS NOT NULL THEN 'poll'
    WHEN EXISTS (SELECT 1 FROM public.beacon_room_message_attachment a
      WHERE a.message_id = lm.id AND a.kind = '''
          '${BeaconRoomMessageAttachmentKind.image}'
          r'''
) THEN 'image'
    WHEN EXISTS (SELECT 1 FROM public.beacon_room_message_attachment a
      WHERE a.message_id = lm.id) THEN 'file'
    WHEN lm.quoted_fact_card_id IS NOT NULL THEN 'fact'
  END AS last_message_kind
FROM unnest($1::text[]) AS ids(beacon_id)
LEFT JOIN LATERAL (
  SELECT m.id, m.created_at, m.body, m.author_id, m.linked_polling_id,
    m.quoted_fact_card_id
  FROM public.beacon_room_message m
  WHERE m.beacon_id = ids.beacon_id
    AND m.thread_item_id IS NULL
    AND m.system_message_kind IS NULL
    AND m.author_id IS NOT NULL
    AND (btrim(m.body) <> ''
      OR m.linked_polling_id IS NOT NULL
      OR m.quoted_fact_card_id IS NOT NULL
      OR EXISTS (SELECT 1 FROM public.beacon_room_message_attachment a
        WHERE a.message_id = m.id))
  ORDER BY m.created_at DESC, m.id DESC
  LIMIT 1
) lm ON true
LEFT JOIN public."user" u ON u.id = lm.author_id
''',
          variables: [
            Variable(TypedValue(Type.textArray, ids)),
            Variable<String>(viewerUserId),
          ],
        )
        .get();
    DateTime? at(Map<String, Object?> data, String column) =>
        switch (data[column]) {
          final DateTime d => d.toUtc(),
          final PgDateTime d => d.dateTime.toUtc(),
          _ => null,
        };
    return {
      for (final row in rows)
        row.data['beacon_id']! as String: RoomLatestActivity(
          lastActivityAt: at(row.data, 'last_activity_at'),
          lastMessageAt: at(row.data, 'last_message_at'),
          lastMessageBody: row.data['last_message_body'] as String?,
          lastMessageAuthorId: row.data['last_message_author_id'] as String?,
          lastMessageAuthorName:
              row.data['last_message_author_name'] as String?,
          lastMessageKind: row.data['last_message_kind'] as String?,
        ),
    };
  }

  // DORMANT(item-threads): item-thread seen upsert branch when threadItemId is non-null.
  // Rooms are General-only (guard: beacon_room_message_general_only_guard, DiscussionScopeDisabledException); thread_item_id is always NULL for new rows. Do not design for this path. See #192.
  @override
  Future<DateTime> markBeaconRoomSeen({
    required String userId,
    required String beaconId,
    required String? threadItemId,
    required DateTime at,
  }) => _db.withMutatingUser(userId, () async {
    // customSelect binds timestamptz as ISO text via ::timestamptz cast.
    final seenAtIso = at.toUtc().toIso8601String();
    final QueryRow row;
    if (threadItemId == null) {
      row = await _db
          .customSelect(
            r'''
INSERT INTO beacon_room_seen (user_id, beacon_id, thread_item_id, last_seen_at)
VALUES ($1, $2, NULL, $3::timestamptz)
ON CONFLICT (user_id, beacon_id) WHERE thread_item_id IS NULL
DO UPDATE SET last_seen_at = GREATEST(
  beacon_room_seen.last_seen_at, EXCLUDED.last_seen_at
)
RETURNING last_seen_at
''',
            variables: [
              Variable<String>(userId),
              Variable<String>(beaconId),
              Variable<String>(seenAtIso),
            ],
          )
          .getSingle();
    } else {
      row = await _db
          .customSelect(
            r'''
INSERT INTO beacon_room_seen (user_id, beacon_id, thread_item_id, last_seen_at)
VALUES ($1, $2, $3, $4::timestamptz)
ON CONFLICT (user_id, beacon_id, thread_item_id) WHERE thread_item_id IS NOT NULL
DO UPDATE SET last_seen_at = GREATEST(
  beacon_room_seen.last_seen_at, EXCLUDED.last_seen_at
)
RETURNING last_seen_at
''',
            variables: [
              Variable<String>(userId),
              Variable<String>(beaconId),
              Variable<String>(threadItemId),
              Variable<String>(seenAtIso),
            ],
          )
          .getSingle();
    }
    return DateTime.parse(row.read<String>('last_seen_at')).toUtc();
  });

  /// Newest main-room message timestamp, or null when the room has no messages.
  Future<DateTime?> latestMainRoomMessageCreatedAt(String beaconId) async {
    final row =
        await (_db.select(_db.beaconRoomMessages)
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
    final rows =
        await (_db.select(_db.beaconRoomSeen)..where(
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

  @override
  Future<List<RoomReadWatermarkRecord>> mainRoomReadWatermarks(
    String beaconId,
  ) async {
    final rows =
        await (_db.select(_db.beaconRoomSeen)
              ..where(
                (s) => s.beaconId.equals(beaconId) & s.threadItemId.isNull(),
              )
              ..orderBy([
                (s) => OrderingTerm(
                  expression: s.lastSeenAt,
                  mode: OrderingMode.desc,
                ),
              ]))
            .get();
    if (rows.isEmpty) {
      return const [];
    }

    final userIds = rows.map((row) => row.userId).toList();
    final titlesByUserId = await userTitlesByIds(userIds);
    final picMetaByUserId = await userPicMetaByIds(userIds);

    return [
      for (final row in rows)
        RoomReadWatermarkRecord(
          userId: row.userId,
          lastSeenAt: row.lastSeenAt.dateTime.toUtc(),
          userTitle: titlesByUserId[row.userId] ?? '',
          userHasPicture: picMetaByUserId[row.userId]?.hasPicture ?? false,
          userPicHeight: picMetaByUserId[row.userId]?.picHeight ?? 0,
          userPicWidth: picMetaByUserId[row.userId]?.picWidth ?? 0,
          userBlurHash: picMetaByUserId[row.userId]?.blurHash ?? '',
          userImageId: picMetaByUserId[row.userId]?.imageId ?? '',
        ),
    ];
  }

  Future<void> markParticipantRoomSeen({
    required String beaconId,
    required String userId,
  }) => markBeaconRoomSeen(
    userId: userId,
    beaconId: beaconId,
    threadItemId: null,
    at: DateTime.timestamp(),
  );

  @override
  Future<BeaconRoomMessageRecord?> getRoomMessageByClientId({
    required String authorId,
    required String clientMessageId,
  }) async =>
      (await (_db.select(_db.beaconRoomMessages)..where(
                (t) =>
                    t.authorId.equals(authorId) &
                    t.clientMessageId.equals(clientMessageId),
              ))
              .getSingleOrNull())
          ?.toRecord();

  Future<BeaconRoomMessageRecord?> getRoomMessageById(String messageId) async =>
      (await _db.managers.beaconRoomMessages
              .filter((m) => m.id.equals(messageId))
              .getSingleOrNull())
          ?.toRecord();

  Future<BeaconRoomMessageRecord?> getRoomMessageByLinkedPollingId(
    String pollingId,
  ) async =>
      (await (_db.select(_db.beaconRoomMessages)
                ..where((t) => t.linkedPollingId.equals(pollingId)))
              .getSingleOrNull())
          ?.toRecord();

  Future<void> markRoomMessageSemanticDone({
    required String messageId,
    required String actingUserId,
  }) => _db.withMutatingUser(actingUserId, () async {
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
    String? factCardId,
    Map<String, Object?>? diff,
  }) => _db.withMutatingUser(actorId, () async {
    await _db.managers.beaconActivityEvents.create(
      (o) => o(
        id: Value(BeaconActivityEventEntity.newId),
        beaconId: beaconId,
        visibility: visibility,
        type: type,
        actorId: Value(actorId),
        targetUserId: Value(targetUserId),
        sourceMessageId: Value(sourceMessageId),
        factCardId: Value(factCardId),
        diff: Value(diff),
        createdAt: const Value.absent(),
      ),
    );
  });

  Future<List<Map<String, Object?>>> listActivityEvents({
    required String beaconId,
    int limit = 200,
  }) async {
    final rows =
        await (_db.select(_db.beaconActivityEvents)
              ..where((e) => e.beaconId.equals(beaconId))
              ..orderBy([
                (e) => OrderingTerm(
                  expression: e.createdAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(limit))
            .get();

    if (rows.isEmpty) return const [];

    final sourceMessageIds = rows
        .map((r) => r.sourceMessageId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

    final messageToItemId = <String, String>{};
    if (sourceMessageIds.isNotEmpty) {
      final messages = await (_db.select(
        _db.beaconRoomMessages,
      )..where((m) => m.id.isIn(sourceMessageIds.toList()))).get();
      for (final message in messages) {
        final linkedItemId = message.linkedItemId?.trim();
        if (linkedItemId != null && linkedItemId.isNotEmpty) {
          messageToItemId[message.id] = linkedItemId;
        }
      }
    }

    final itemIds = <String>{};
    for (final row in rows) {
      final storedItemId = row.coordinationItemId?.trim();
      if (storedItemId != null && storedItemId.isNotEmpty) {
        itemIds.add(storedItemId);
      }
      final sourceMessageId = row.sourceMessageId;
      if (sourceMessageId != null) {
        final linkedItemId = messageToItemId[sourceMessageId];
        if (linkedItemId != null) itemIds.add(linkedItemId);
      }
    }

    final itemsById = <String, CoordinationItem>{};
    if (itemIds.isNotEmpty) {
      final items = await (_db.select(
        _db.coordinationItems,
      )..where((t) => t.id.isIn(itemIds.toList()))).get();
      for (final item in items) {
        itemsById[item.id] = item;
      }
    }

    return [
      for (final row in rows)
        _activityEventToMap(
          row,
          messageToItemId: messageToItemId,
          itemsById: itemsById,
        ),
    ];
  }

  Map<String, Object?> _activityEventToMap(
    BeaconActivityEvent row, {
    required Map<String, String> messageToItemId,
    required Map<String, CoordinationItem> itemsById,
  }) {
    final storedItemId = row.coordinationItemId?.trim();
    final itemId = storedItemId != null && storedItemId.isNotEmpty
        ? storedItemId
        : (row.sourceMessageId != null
              ? messageToItemId[row.sourceMessageId!]
              : null);

    var diff = row.diff;
    if (diff == null && itemId != null) {
      final item = itemsById[itemId];
      if (item != null) {
        diff = _activityEventDiffMap(title: item.title, body: item.body);
      }
    }

    return {
      'id': row.id,
      'beaconId': row.beaconId,
      'visibility': row.visibility,
      'type': row.type,
      'actorId': row.actorId,
      'targetUserId': row.targetUserId,
      'sourceMessageId': row.sourceMessageId,
      'coordinationItemId': itemId,
      'diffJson': diff == null ? null : jsonEncode(diff),
      'createdAt': row.createdAt.dateTime.toUtc().toIso8601String(),
    };
  }

  Map<String, Object?>? _activityEventDiffMap({
    required String title,
    String body = '',
  }) {
    final trimmedTitle = title.trim();
    final trimmedBody = body.trim();
    if (trimmedTitle.isEmpty && trimmedBody.isEmpty) return null;
    return {
      if (trimmedTitle.isNotEmpty) 'title': trimmedTitle,
      if (trimmedBody.isNotEmpty) 'body': trimmedBody,
    };
  }

  String? _activityEventDiffJson(Object? diff) {
    if (diff == null) return null;
    if (diff is Map) {
      if (diff.isEmpty) return null;
      return jsonEncode(diff);
    }
    return diff.toString();
  }

  Future<String?> beaconAuthorUserId(String beaconId) async {
    final b = await _db.managers.beacons
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

  /// Latest meaningful log event per beacon for My Work cards.
  ///
  /// Predicate mirrors client [`BeaconActivityEvent.isCoordinationLogEvent`].
  Future<List<MyWorkLastActivityEventRow>> latestActivityEventsByBeaconIds({
    required List<String> beaconIds,
    required String viewerUserId,
  }) async {
    if (beaconIds.isEmpty) {
      return const [];
    }

    final eventsByBeacon = <String, BeaconActivityEventRecord?>{};
    final actorIds = <String>{};

    for (final beaconId in beaconIds) {
      final canUseRoom = await _viewerCanUseRoom(
        beaconId: beaconId,
        userId: viewerUserId,
      );

      final meaningfulTypes = [
        BeaconActivityEventTypeBits.planUpdated,
        BeaconActivityEventTypeBits.factPinned,
        BeaconActivityEventTypeBits.blockerOpened,
        BeaconActivityEventTypeBits.blockerResolved,
        BeaconActivityEventTypeBits.needInfoOpened,
        BeaconActivityEventTypeBits.doneMarked,
        BeaconActivityEventTypeBits.factVisibilityChanged,
        BeaconActivityEventTypeBits.beaconPublished,
        BeaconActivityEventTypeBits.beaconLifecycleChanged,
      ];

      final row =
          await (_db.select(_db.beaconActivityEvents)
                ..where(
                  (e) {
                    final meaningful =
                        (e.type.isBiggerOrEqualValue(100) &
                            e.type.isSmallerThanValue(500)) |
                        e.type.isIn(meaningfulTypes);
                    final visible = canUseRoom
                        ? e.visibility.isIn([
                            BeaconActivityEventVisibilityBits.public,
                            BeaconActivityEventVisibilityBits.room,
                          ])
                        : e.visibility.equals(
                            BeaconActivityEventVisibilityBits.public,
                          );
                    return e.beaconId.equals(beaconId) & meaningful & visible;
                  },
                )
                ..orderBy([
                  (e) => OrderingTerm(
                    expression: e.createdAt,
                    mode: OrderingMode.desc,
                  ),
                ])
                ..limit(1))
              .getSingleOrNull();

      if (row == null) {
        eventsByBeacon[beaconId] = null;
        continue;
      }

      final record = BeaconActivityEventRecord(
        id: row.id,
        beaconId: row.beaconId,
        visibility: row.visibility,
        type: row.type,
        actorId: row.actorId,
        diffJson: _activityEventDiffJson(row.diff),
        createdAt: row.createdAt.dateTime.toUtc(),
      );
      eventsByBeacon[beaconId] = record;
      final actorId = row.actorId;
      if (actorId != null && actorId.isNotEmpty) {
        actorIds.add(actorId);
      }
    }

    final titles = await userTitlesByIds(actorIds);
    final pics = await userPicMetaByIds(actorIds);

    return [
      for (final beaconId in beaconIds)
        () {
          final event = eventsByBeacon[beaconId];
          final actorId = event?.actorId;
          return MyWorkLastActivityEventRow(
            beaconId: beaconId,
            event: event,
            actorTitle: actorId == null ? null : titles[actorId],
            actorImageId: actorId == null ? null : pics[actorId]?.imageId,
          );
        }(),
    ];
  }

  Future<bool> _viewerCanUseRoom({
    required String beaconId,
    required String userId,
  }) async {
    if (await isBeaconAuthor(beaconId: beaconId, userId: userId)) {
      return true;
    }
    if (await isBeaconSteward(beaconId: beaconId, userId: userId)) {
      return true;
    }
    final participant = await findParticipant(
      beaconId: beaconId,
      userId: userId,
    );
    return participant?.roomAccess == RoomAccessBits.admitted;
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
      final rows =
          await (_db.select(_db.beaconRoomMessages)..where((m) {
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
    final rows =
        await (_db.select(_db.beaconRoomMessages)..where((m) {
              var cond =
                  m.beaconId.equals(beaconId) &
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

  @override
  Future<int> countRecentMessagesByAuthor({
    required String authorId,
    required Duration window,
  }) async {
    final since = DateTime.timestamp().subtract(window);
    final rows = await _db
        .customSelect(
          '''
SELECT COUNT(*)::int AS c
FROM public.beacon_room_message
WHERE author_id = \$1 AND created_at >= \$2
''',
          variables: [
            Variable<String>(authorId),
            Variable(TypedValue(Type.timestampTz, since)),
          ],
        )
        .getSingle();
    return rows.read<int>('c');
  }

  Future<int> countAttachmentsForMessage(String messageId) async {
    final rows = await (_db.select(
      _db.beaconRoomMessageAttachments,
    )..where((a) => a.messageId.equals(messageId))).get();
    return rows.length;
  }

  Future<BeaconRoomMessageAttachmentRecord?> getRoomMessageAttachmentById(
    String attachmentId,
  ) async => (await (_db.select(
    _db.beaconRoomMessageAttachments,
  )..where((a) => a.id.equals(attachmentId))).getSingleOrNull())?.toRecord();

  Future<void> insertRoomMessageAttachmentImage({
    required String attachmentId,
    required String messageId,
    required int position,
    required String imageId,
    required String mime,
    required int sizeBytes,
    required String displayName,
    required String mutatingUserId,
  }) => _db.withMutatingUser(mutatingUserId, () async {
    await _db
        .into(_db.beaconRoomMessageAttachments)
        .insert(
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
  }) => _db.withMutatingUser(mutatingUserId, () async {
    await _db
        .into(_db.beaconRoomMessageAttachments)
        .insert(
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
