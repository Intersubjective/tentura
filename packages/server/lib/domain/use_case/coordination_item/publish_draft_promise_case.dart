import 'dart:async';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';

import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_port.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class PublishDraftPromiseCase extends UseCaseBase {
  PublishDraftPromiseCase(
    this._beaconRepository,
    this._itemRepository,
    this._push, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final CoordinationItemRepositoryPort _itemRepository;
  final BeaconRoomNotificationPort _push;

  Future<CoordinationItemRecord> call({
    required String userId,
    required String itemId,
    required String targetPersonId,
    int? staleAfterDays,
  }) async {
    final target = targetPersonId.trim();
    if (target.isEmpty) {
      throw const BeaconCreateException(
        description: 'Promise target person is required',
      );
    }
    final existing = await _itemRepository.getById(itemId);
    if (existing == null) {
      throw const BeaconCreateException(description: 'Promise not found');
    }
    if (existing.kind != coordinationItemKindPromise) {
      throw const BeaconCreateException(
        description: 'Only promises can be published',
      );
    }
    if (existing.published) {
      throw const BeaconCreateException(
        description: 'This promise is already live',
      );
    }
    if (existing.creatorId != userId) {
      throw const BeaconCreateException(
        description: 'Only the draft author can publish this promise',
      );
    }
    if (target == userId) {
      throw const BeaconCreateException(
        description: 'Promise cannot target yourself',
      );
    }
    final beacon =
        await _beaconRepository.getBeaconById(beaconId: existing.beaconId);
    if (!beacon.allowsCoordination) {
      throw const BeaconCreateException(description: 'Request is not open');
    }
    final item = await _itemRepository.publishDraft(
      id: itemId,
      actorId: userId,
      targetPersonId: target,
      staleAfterDays: staleAfterDays,
    );
    unawaited(
      _push.notifyPromiseMade(
        beaconId: item.beaconId,
        actorUserId: userId,
        excerpt: item.title,
        targetPersonId: target,
        coordinationItemId: item.id,
      ),
    );
    return item;
  }
}
