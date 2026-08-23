import 'package:injectable/injectable.dart';

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
    if (row == null || row.body.trim().isEmpty) {
      return null;
    }
    if (row.linkedNextMoveId != null ||
        row.linkedFactCardId != null ||
        row.linkedPollingId != null ||
        row.linkedItemId != null ||
        row.linkedEventKind != null ||
        row.semanticMarker != null ||
        row.systemPayload != null) {
      return null;
    }

    final attachmentRows = await (_database.select(
      _database.beaconRoomMessageAttachments,
    )..where((a) => a.messageId.equals(messageId))).get();
    if (attachmentRows.isNotEmpty) {
      return null;
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
      authorId: row.authorId,
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
      authorId: parent.authorId,
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
