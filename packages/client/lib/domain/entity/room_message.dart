import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/domain/entity/room_message_hierarchy_payload.dart';
import 'package:tentura/domain/entity/room_message_mention_span.dart';

part 'room_message.freezed.dart';

@freezed
abstract class RoomMessage with _$RoomMessage {
  const factory RoomMessage({
    required String id,
    required String beaconId,
    required String authorId,
    required String body,
    required DateTime createdAt,
    DateTime? editedAt,
    @Default(Profile()) Profile author,
    @Default(<String, int>{}) Map<String, int> reactionCounts,
    String? myReaction,
    @Default(<String, List<Profile>>{}) Map<String, List<Profile>> reactors,
    int? semanticMarker,
    String? linkedBlockerId,
    String? linkedFactCardId,
    String? linkedPollingId,
    String? pollDataJson,
    String? linkedItemId,
    int? linkedEventKind,
    int? linkedItemKind,
    int? linkedItemStatus,
    String? linkedItemTitle,
    String? linkedItemBody,
    String? linkedItemCreatorId,
    String? linkedItemTargetPersonId,
    DateTime? linkedItemCreatedAt,
    DateTime? linkedItemUpdatedAt,
    String? linkedItemLinkedMessageId,
    DateTime? linkedItemResolvedAt,
    // Joined client-side from `listByBeacon` during room load (not in the gql
    // message snapshot); drive the thread-mark reply count + unread dot.
    @Default(0) int linkedItemMessageCount,
    @Default(0) int linkedItemUnreadCount,
    String? systemPayloadJson,
    int? systemMessageKind,
    @Default(<RoomMessageAttachment>[]) List<RoomMessageAttachment> attachments,
    @Default(<String>[]) List<String> mentions,
    @Default(<RoomMessageMentionSpan>[])
    List<RoomMessageMentionSpan> mentionSpans,
    String? threadItemId,
    String? replyToMessageId,
    String? replyToAuthorId,
    String? replyToAuthorTitle,
    String? replyToBodyExcerpt,
    @Default(false) bool replyToHasAttachments,
  }) = _RoomMessage;

  const RoomMessage._();

  bool get isReply => (replyToMessageId ?? '').trim().isNotEmpty;

  /// Known to be a reply, but the parent snapshot did not resolve — deleted
  /// between list and read, or rejected by the server scope filter.
  bool get replyTargetUnavailable =>
      isReply && (replyToAuthorId ?? '').trim().isEmpty;

  /// Server `beacon_room_message.system_payload`: promote pin line contains
  /// `{"sourceMessageId":"<id>"}` pointing at the in-place linked message.
  String? get sourceMessageId {
    final raw = systemPayloadJson;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final id = decoded['sourceMessageId'];
      if (id is String && id.trim().isNotEmpty) return id.trim();
      return null;
    } on Object {
      return null;
    }
  }

  /// Latest coordination status on the promoted source message (server merge).
  ({int eventKind, String actorId, DateTime at})? get lastStatusEvent {
    final raw = systemPayloadJson;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final block = decoded['lastStatusEvent'];
      if (block is! Map<String, dynamic>) return null;
      final ek = block['eventKind'];
      final actor = block['actorId'];
      final at = block['at'];
      if (ek is! num || actor is! String || at is! String) return null;
      final parsedAt = DateTime.tryParse(at);
      if (parsedAt == null) return null;
      return (
        eventKind: ek.toInt(),
        actorId: actor.trim(),
        at: parsedAt,
      );
    } on Object {
      return null;
    }
  }

  /// Promoted source or standalone creation row (not a timeline notify).
  bool get isPromotedSourceMessage {
    final lid = linkedItemId?.trim();
    if (lid == null || lid.isEmpty) return false;

    final src = sourceMessageId?.trim();
    if (src != null && src.isNotEmpty && id != src) return false;

    final item = linkedCoordinationItem;
    if (item == null) return false;

    final itemAnchor = item.linkedMessageId?.trim();
    if (itemAnchor != null && itemAnchor.isNotEmpty) {
      return id == itemAnchor;
    }

    return linkedEventKind == CoordinationItemEventKind.created.value;
  }

  /// Who set [semanticMarker] (e.g. mark-done); from `system_payload.semanticActorId`.
  String? get semanticActorId {
    final raw = systemPayloadJson;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final id = decoded['semanticActorId'];
      if (id is String && id.trim().isNotEmpty) return id.trim();
      return null;
    } on Object {
      return null;
    }
  }

  /// Typed `system_payload` for a hierarchy notice row
  /// (`systemMessageKind == hierarchyLifecycle|childCreated`, plan §4.1/§4.4).
  /// Any unknown/unparseable `kind`, `version`, or shape returns null so the
  /// caller falls back to generic, non-actionable system-event text —
  /// never throws.
  RoomMessageHierarchyPayload? get hierarchyPayload {
    if (systemMessageKind != BeaconRoomSystemMessageKind.hierarchyLifecycle &&
        systemMessageKind != BeaconRoomSystemMessageKind.childCreated) {
      return null;
    }
    final raw = systemPayloadJson;
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      if (decoded['version'] != 1) return null;
      switch (decoded['kind']) {
        case 'childCreated':
          final childBeaconId = decoded['childBeaconId'];
          if (childBeaconId is! String || childBeaconId.trim().isEmpty) {
            return null;
          }
          final sourceMessageId = decoded['sourceMessageId'];
          return RoomMessageHierarchyChildCreated(
            childBeaconId: childBeaconId.trim(),
            sourceMessageId: sourceMessageId is String && sourceMessageId.trim().isNotEmpty
                ? sourceMessageId.trim()
                : null,
          );
        case 'hierarchyLifecycle':
          final eventId = decoded['eventId'];
          final targetBeaconId = decoded['targetBeaconId'];
          final direction = decoded['direction'];
          final toStatus = decoded['toStatus'];
          final occurredAt = decoded['occurredAt'];
          final sourceDeleted = decoded['sourceDeleted'];
          if (eventId is! String ||
              targetBeaconId is! String ||
              direction is! String ||
              toStatus is! String ||
              occurredAt is! String ||
              sourceDeleted is! bool) {
            return null;
          }
          final parsedAt = DateTime.tryParse(occurredAt);
          if (parsedAt == null) return null;
          return RoomMessageHierarchyLifecycle(
            eventId: eventId,
            targetBeaconId: targetBeaconId,
            direction: direction,
            toStatus: toStatus,
            occurredAt: parsedAt,
            sourceDeleted: sourceDeleted,
          );
        default:
          return null;
      }
    } on Object {
      return null;
    }
  }

  /// When [linkedItemId] is set and snapshot fields are present, reconstructs
  /// the linked coordination item for navigation / inline cards.
  CoordinationItem? get linkedCoordinationItem {
    final lid = linkedItemId;
    if (lid == null || lid.isEmpty) return null;
    final k = linkedItemKind;
    final s = linkedItemStatus;
    final c = linkedItemCreatorId;
    final ca = linkedItemCreatedAt;
    final ua = linkedItemUpdatedAt;
    if (k == null || s == null || c == null || ca == null || ua == null) {
      return null;
    }
    return CoordinationItem(
      id: lid,
      beaconId: beaconId,
      kind: CoordinationItemKind.fromInt(k),
      status: CoordinationItemStatus.fromInt(s),
      creatorId: c,
      targetPersonId: linkedItemTargetPersonId,
      createdAt: ca,
      updatedAt: ua,
      title: linkedItemTitle ?? '',
      body: linkedItemBody ?? '',
      linkedMessageId: linkedItemLinkedMessageId,
      resolvedAt: linkedItemResolvedAt,
      messageCount: linkedItemMessageCount,
      unreadCount: linkedItemUnreadCount,
    );
  }
}
