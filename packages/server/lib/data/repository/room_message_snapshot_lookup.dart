import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/entity/quoted_fact_entity.dart';

import 'package:tentura_server/domain/entity/room_message_snapshot.dart';
import 'package:tentura_server/domain/port/room_message_snapshot_lookup_port.dart';
import 'package:tentura_server/domain/util/room_reply_excerpt.dart';

import '../database/tentura_db.dart';

@LazySingleton(as: RoomMessageSnapshotLookupPort)
final class RoomMessageSnapshotLookup implements RoomMessageSnapshotLookupPort {
  RoomMessageSnapshotLookup(this._database);

  final TenturaDb _database;

  @override
  Future<RoomMessageSnapshot?> findEligibleInsert({
    required String messageId,
    required String beaconId,
  }) async {
    final row =
        await (_database.select(_database.beaconRoomMessages)..where(
              (m) => m.id.equals(messageId) & m.beaconId.equals(beaconId),
            ))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }
    if (row.linkedNextMoveId != null ||
        row.linkedFactCardId != null ||
        row.linkedPollingId != null ||
        row.linkedItemId != null ||
        row.linkedEventKind != null) {
      return null;
    }
    // Only fact edit/unpin system lines and Request plan lines (#220, kind 5,
    // markers 13..16, author may be null) paint; pin lines (2/3) and every
    // other marker stay client refetch.
    final marker = row.semanticMarker;
    final isPlanLine =
        row.systemMessageKind == _planSystemMessageKind &&
        _planMarkers.contains(marker);
    final isFactSystemLine =
        isPlanLine ||
        marker == BeaconRoomSemanticMarker.factEdited ||
        marker == BeaconRoomSemanticMarker.factUnpinned;
    final systemPayload = _decodeSystemPayload(row.systemPayload);
    if (isFactSystemLine) {
      if (systemPayload == null) {
        return null;
      }
    } else if (marker != null || row.systemPayload != null) {
      return null;
    }
    final quotedFactCardId = row.quotedFactCardId;
    final quotedFactRevisionSeq = row.quotedFactRevisionSeq;
    final isQuote = quotedFactCardId != null && quotedFactRevisionSeq != null;
    if (row.body.trim().isEmpty && !isFactSystemLine && !isQuote) {
      return null;
    }

    final attachmentRows = await (_database.select(
      _database.beaconRoomMessageAttachments,
    )..where((a) => a.messageId.equals(messageId))).get();
    if (attachmentRows.isNotEmpty) {
      return null;
    }

    QuotedFactEntity? quotedFact;
    if (isQuote) {
      quotedFact = await _resolveQuotedFact(
        factCardId: quotedFactCardId,
        seq: quotedFactRevisionSeq,
        beaconId: row.beaconId,
      );
      if (quotedFact == null) {
        return null;
      }
    }

    String? replyToMessageId;
    String? replyToAuthorId;
    String? replyToAuthorTitle;
    String? replyToBodyExcerpt;
    var replyToHasAttachments = false;
    final parentId = row.replyToMessageId;
    if (parentId != null && parentId.isNotEmpty) {
      replyToMessageId = parentId;
      final parent = await _resolveScopedParentReply(
        parentMessageId: parentId,
        beaconId: row.beaconId,
        threadItemId: row.threadItemId,
      );
      if (parent != null) {
        replyToAuthorId = parent.authorId;
        replyToAuthorTitle = parent.authorTitle;
        replyToBodyExcerpt = parent.bodyExcerpt;
        replyToHasAttachments = parent.hasAttachments;
      }
    }

    return RoomMessageSnapshot(
      id: row.id,
      beaconId: row.beaconId,
      authorId: row.authorId ?? '',
      body: row.body,
      createdAt: row.createdAt.dateTime,
      editedAt: row.editedAt?.dateTime,
      mentions: List<String>.from(row.mentions),
      mentionSpans: row.mentionSpans == null
          ? const []
          : [
              for (final raw in row.mentionSpans! as List)
                if (raw is Map) Map<String, Object?>.from(raw),
            ],
      threadItemId: row.threadItemId,
      replyToMessageId: replyToMessageId,
      replyToAuthorId: replyToAuthorId,
      replyToAuthorTitle: replyToAuthorTitle,
      replyToBodyExcerpt: replyToBodyExcerpt,
      replyToHasAttachments: replyToHasAttachments,
      semanticMarker: isFactSystemLine ? marker : null,
      systemPayload: isFactSystemLine ? systemPayload : null,
      systemMessageKind: isPlanLine ? row.systemMessageKind : null,
      quotedFact: quotedFact,
    );
  }

  /// `beacon_room_message.system_message_kind` of Request plan lines.
  static const _planSystemMessageKind = 5;

  static const _planMarkers = {
    BeaconRoomSemanticMarker.planRevised,
    BeaconRoomSemanticMarker.planStepsDone,
    BeaconRoomSemanticMarker.planCantMake,
    BeaconRoomSemanticMarker.planCopied,
  };

  static Map<String, Object?>? _decodeSystemPayload(Object? raw) {
    final decoded = raw is String ? jsonDecode(raw) : raw;
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  }

  /// One-row quote snapshot mirroring `listMessagesEnriched` `quotedFact`.
  /// Returns null when the revision is missing.
  Future<QuotedFactEntity?> _resolveQuotedFact({
    required String factCardId,
    required int seq,
    required String beaconId,
  }) async {
    final row = await _database
        .customSelect(
          r'''
SELECT
  r.fact_text, f.pinned_by, u.display_name AS pinned_by_title,
  f.visibility::integer AS visibility, f.status::integer AS status,
  f.revision_seq::integer AS current_seq,
  COALESCE(r.attachments_json::text, '[]') AS attachments_json
FROM public.beacon_fact_card_revision r
JOIN public.beacon_fact_card f ON f.id = r.fact_card_id
LEFT JOIN public."user" u ON u.id = f.pinned_by
WHERE r.fact_card_id = $1::text AND r.seq = $2::integer
  AND f.beacon_id = $3::text
''',
          variables: [
            Variable<String>(factCardId),
            Variable<int>(seq),
            Variable<String>(beaconId),
          ],
        )
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    final pinnedById = row.readNullable<String>('pinned_by');
    return QuotedFactEntity(
      factCardId: factCardId,
      seq: seq,
      factText: row.read<String>('fact_text'),
      pinnedById: pinnedById,
      pinnedByTitle: row.readNullable<String>('pinned_by_title') ?? '',
      visibility: row.read<int>('visibility'),
      status: row.read<int>('status'),
      currentSeq: row.read<int>('current_seq'),
      attachmentsJson: row.read<String>('attachments_json'),
    );
  }

  Future<
    ({
      String authorId,
      String authorTitle,
      String? bodyExcerpt,
      bool hasAttachments,
    })?
  >
  // DORMANT(item-threads): thread-scoped parent reply resolution filter.
  // Rooms are General-only (guard: beacon_room_message_general_only_guard, DiscussionScopeDisabledException); thread_item_id is always NULL for new rows. Do not design for this path. See #192.
  _resolveScopedParentReply({
    required String parentMessageId,
    required String beaconId,
    required String? threadItemId,
  }) async {
    Expression<bool> threadFilter($BeaconRoomMessagesTable m) {
      final tid = threadItemId;
      if (tid == null) {
        return m.threadItemId.isNull();
      }
      return m.threadItemId.equals(tid);
    }

    final joined =
        await (_database.select(_database.beaconRoomMessages).join([
              innerJoin(
                _database.users,
                _database.users.id.equalsExp(
                  _database.beaconRoomMessages.authorId,
                ),
              ),
            ])..where(
              _database.beaconRoomMessages.id.equals(parentMessageId) &
                  _database.beaconRoomMessages.beaconId.equals(beaconId) &
                  threadFilter(_database.beaconRoomMessages),
            ))
            .getSingleOrNull();
    if (joined == null) {
      return null;
    }

    final parent = joined.readTable(_database.beaconRoomMessages);
    final author = joined.readTable(_database.users);
    final attachmentIds = await _messageIdsWithAttachments([parentMessageId]);

    return (
      authorId: parent.authorId ?? '',
      authorTitle: author.displayName,
      bodyExcerpt: roomReplyExcerpt(parent.body),
      hasAttachments: attachmentIds.contains(parentMessageId),
    );
  }

  Future<Set<String>> _messageIdsWithAttachments(List<String> ids) async {
    final filtered = ids.where((id) => id.isNotEmpty).toSet().toList();
    if (filtered.isEmpty) {
      return {};
    }
    final rows = await (_database.select(
      _database.beaconRoomMessageAttachments,
    )..where((a) => a.messageId.isIn(filtered))).get();
    return {for (final row in rows) row.messageId};
  }
}
