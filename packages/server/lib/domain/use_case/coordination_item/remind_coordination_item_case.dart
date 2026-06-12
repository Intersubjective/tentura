import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/service/beacon_room_push_service.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/coordination_stale_rules.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../_use_case_base.dart';
import 'coordination_room_access.dart';

@Singleton(order: 2)
final class RemindCoordinationItemCase extends UseCaseBase {
  RemindCoordinationItemCase(
    this._itemRepository,
    this._roomRepository,
    this._push, {
    required super.env,
    required super.logger,
  });

  final CoordinationItemRepositoryPort _itemRepository;
  final BeaconRoomRepository _roomRepository;
  final BeaconRoomPushService _push;

  Future<CoordinationItem> call({
    required String userId,
    required String itemId,
  }) async {
    final existing = await _itemRepository.getById(itemId);
    if (existing == null) {
      throw const IdNotFoundException(description: 'Coordination item not found');
    }
    if (!isRemindableKind(existing.kind)) {
      throw const BeaconCreateException(
        description: 'Only asks, promises, and blockers can be reminded',
      );
    }

    await ensureCanCoordinateOnBeacon(
      room: _roomRepository,
      beaconId: existing.beaconId,
      userId: userId,
    );

    final view = _toView(existing);
    if (!isItemStale(view, DateTime.timestamp().toUtc())) {
      throw const BeaconCreateException(
        description: 'Item is not stale yet',
      );
    }

    final responsible = resolveResponsibleUserId(view);
    if (responsible == null || responsible.isEmpty) {
      throw const BeaconCreateException(
        description: 'No one is responsible for this item',
      );
    }
    if (responsible == userId) {
      throw const BeaconCreateException(
        description: 'You cannot remind yourself',
      );
    }

    final claimed = await _itemRepository.tryClaimRemind(
      itemId: itemId,
      actorId: userId,
    );
    if (claimed == null) {
      throw const BeaconCreateException(
        description: 'Reminder was sent recently — try again later',
      );
    }

    final excerpt = claimed.title.trim().isNotEmpty
        ? claimed.title.trim()
        : claimed.body.trim();
    unawaited(
      _push.notifyStaleRemind(
        beaconId: claimed.beaconId,
        actorUserId: userId,
        targetPersonId: responsible,
        coordinationItemId: claimed.id,
        excerpt: excerpt,
      ),
    );
    return claimed;
  }

  CoordinationStaleItemView _toView(CoordinationItem item) =>
      CoordinationStaleItemView(
        kind: item.kind,
        status: item.status,
        creatorId: item.creatorId,
        targetPersonId: item.targetPersonId,
        acceptedById: item.acceptedById,
        staleAt: item.staleAt?.dateTime.toUtc(),
        staleAfterDays: item.staleAfterDays,
      );
}
