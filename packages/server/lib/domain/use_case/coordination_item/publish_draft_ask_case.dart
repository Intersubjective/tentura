import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:tentura_server/data/service/beacon_room_push_service.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class PublishDraftAskCase extends UseCaseBase {
  PublishDraftAskCase(
    this._beaconRepository,
    this._itemRepository,
    this._push, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final CoordinationItemRepositoryPort _itemRepository;
  final BeaconRoomPushService _push;

  Future<CoordinationItem> call({
    required String userId,
    required String itemId,
    required String targetPersonId,
    int? staleAfterDays,
  }) async {
    final target = targetPersonId.trim();
    if (target.isEmpty) {
      throw const BeaconCreateException(
        description: 'Ask target person is required',
      );
    }
    final existing = await _itemRepository.getById(itemId);
    if (existing == null) {
      throw const BeaconCreateException(description: 'Ask not found');
    }
    if (existing.kind != coordinationItemKindAsk) {
      throw const BeaconCreateException(
        description: 'Only asks can be published',
      );
    }
    if (existing.published) {
      throw const BeaconCreateException(
        description: 'This ask is already live',
      );
    }
    if (existing.creatorId != userId) {
      throw const BeaconCreateException(
        description: 'Only the draft author can publish this ask',
      );
    }
    final beacon =
        await _beaconRepository.getBeaconById(beaconId: existing.beaconId);
    if (!beacon.isActive) {
      throw const BeaconCreateException(description: 'Beacon is not open');
    }
    final item = await _itemRepository.publishDraft(
      id: itemId,
      actorId: userId,
      targetPersonId: target,
      staleAfterDays: staleAfterDays,
    );
    if (target != userId) {
      unawaited(
        _push.notifyNeedsMe(
          beaconId: item.beaconId,
          actorUserId: userId,
          targetUserId: target,
          excerpt: item.title,
          coordinationItemId: item.id,
        ),
      );
    }
    return item;
  }
}
