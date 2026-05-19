import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:tentura_server/data/service/beacon_room_push_service.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class CancelPromiseCase extends UseCaseBase {
  CancelPromiseCase(
    this._itemRepository,
    this._push, {
    required super.env,
    required super.logger,
  });

  final CoordinationItemRepositoryPort _itemRepository;
  final BeaconRoomPushService _push;

  Future<CoordinationItem> call({
    required String userId,
    required String itemId,
    String reason = '',
  }) async {
    final item = await _itemRepository.getById(itemId);
    if (item == null) {
      throw const IdNotFoundException(description: 'Promise not found');
    }
    if (item.kind != coordinationItemKindPromise) {
      throw const BeaconCreateException(description: 'Item is not a promise');
    }
    if (item.status == coordinationItemStatusResolved ||
        item.status == coordinationItemStatusCancelled) {
      throw const BeaconCreateException(description: 'Promise is already closed');
    }
    final updated = await _itemRepository.updateStatus(
      id: itemId,
      newStatus: coordinationItemStatusCancelled,
      actorId: userId,
    );
    unawaited(
      _push.notifyPromiseMade(
        beaconId: updated.beaconId,
        actorUserId: userId,
        excerpt: updated.title,
        targetPersonId: updated.targetPersonId,
        coordinationItemId: updated.id,
        withdrawn: true,
      ),
    );
    return updated;
  }
}
