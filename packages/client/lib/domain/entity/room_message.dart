import 'dart:convert';

import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';

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
    DateTime? linkedItemCreatedAt,
    DateTime? linkedItemUpdatedAt,
    String? systemPayloadJson,
    @Default(<RoomMessageAttachment>[]) List<RoomMessageAttachment> attachments,
    @Default(<String>[]) List<String> mentions,
  }) = _RoomMessage;

  const RoomMessage._();

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
      createdAt: ca,
      updatedAt: ua,
      title: linkedItemTitle ?? '',
      body: linkedItemBody ?? '',
    );
  }
}
