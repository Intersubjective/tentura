import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/entity/coordination_item_with_counts.dart';
import 'package:tentura_server/domain/entity/coordination_responsibility_counts.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../_use_case_base.dart';
import 'coordination_room_access.dart';

@Singleton(order: 2)
final class CoordinationResponsibilityCase extends UseCaseBase {
  CoordinationResponsibilityCase(
    this._items,
    this._room, {
    required super.env,
    required super.logger,
  });

  final CoordinationItemRepositoryPort _items;
  final BeaconRoomRepositoryPort _room;

  Future<List<CoordinationResponsibilityCounts>> batch({
    required String viewerUserId,
    required List<String> beaconIds,
  }) async {
    if (beaconIds.isEmpty) {
      return const [];
    }
    final unique = beaconIds.toSet().toList();
    final slice = unique.length > 80 ? unique.sublist(0, 80) : unique;
    for (final bid in slice) {
      await ensureCanCoordinateOnBeacon(
        room: _room,
        beaconId: bid,
        userId: viewerUserId,
      );
    }
    return _items.responsibilityCountsByBeaconIds(
      viewerUserId: viewerUserId,
      beaconIds: slice,
    );
  }

  Future<List<CoordinationItemWithCounts>> myItems({
    required String viewerUserId,
    required String beaconId,
  }) async {
    await ensureCanCoordinateOnBeacon(
      room: _room,
      beaconId: beaconId,
      userId: viewerUserId,
    );
    return _items.myResponsibilityItemsByBeacon(
      viewerUserId: viewerUserId,
      beaconId: beaconId,
    );
  }

  Future<DateTime> markSeen({
    required String viewerUserId,
    required String beaconId,
  }) async {
    await ensureCanCoordinateOnBeacon(
      room: _room,
      beaconId: beaconId,
      userId: viewerUserId,
    );
    return _items.markBeaconItemsSeen(
      userId: viewerUserId,
      beaconId: beaconId,
    );
  }
}
