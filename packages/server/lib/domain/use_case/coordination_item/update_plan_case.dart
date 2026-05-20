import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/service/beacon_room_push_service.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import 'coordination_room_access.dart';
import '../_use_case_base.dart';

@Singleton(order: 2)
final class UpdatePlanCase extends UseCaseBase {
  UpdatePlanCase(
    this._beaconRepository,
    this._itemRepository,
    this._room,
    this._push, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final CoordinationItemRepositoryPort _itemRepository;
  final BeaconRoomRepository _room;
  final BeaconRoomPushService _push;

  Future<CoordinationItem> call({
    required String userId,
    required String beaconId,
    required String title,
    String body = '',
    String? targetPersonId,
    String? linkedMessageId,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw const BeaconCreateException(description: 'Plan text is required');
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (!beacon.isActive) {
      throw const BeaconCreateException(description: 'Beacon is not open');
    }
    await ensureCanCoordinateOnBeacon(
      room: _room,
      beaconId: beaconId,
      userId: userId,
    );
    final item = await _itemRepository.publishRootPlan(
      beaconId: beaconId,
      creatorId: userId,
      title: trimmed,
      body: body.trim(),
      targetPersonId: targetPersonId,
      linkedMessageId: linkedMessageId,
      syncCurrentLineText: trimmed,
    );
    unawaited(
      _push.notifyPlanUpdatedToRoom(
        beaconId: beaconId,
        actorUserId: userId,
        admittedUserIds: const [],
        planExcerpt: trimmed,
      ),
    );
    return item;
  }
}
