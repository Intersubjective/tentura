import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';

CoordinationItemRecord testCoordinationItem({
  required String id,
  required String beaconId,
  required int kind,
  required String creatorId,
  int status = coordinationItemStatusOpen,
  String title = '',
  String body = '',
  String? targetPersonId,
  String? acceptedById,
  String? linkedParentItemId,
  int ordering = 0,
  int source = coordinationItemSourceDefault,
  bool published = true,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? staleAt,
  int? staleAfterDays,
}) =>
    CoordinationItemRecord(
      id: id,
      beaconId: beaconId,
      kind: kind,
      status: status,
      title: title,
      body: body,
      creatorId: creatorId,
      targetPersonId: targetPersonId,
      acceptedById: acceptedById,
      linkedParentItemId: linkedParentItemId,
      ordering: ordering,
      source: source,
      published: published,
      createdAt: createdAt ?? DateTime.utc(2026),
      updatedAt: updatedAt ?? DateTime.utc(2026),
      staleAt: staleAt,
      staleAfterDays: staleAfterDays,
    );

BeaconParticipantRecord testBeaconParticipant({
  required String beaconId,
  required String userId,
  int roomAccess = RoomAccessBits.admitted,
  String id = 'P1',
}) =>
    BeaconParticipantRecord(
      id: id,
      beaconId: beaconId,
      userId: userId,
      role: 0,
      status: 0,
      roomAccess: roomAccess,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
