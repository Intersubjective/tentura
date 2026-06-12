import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/service/beacon_room_push_service.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class MarkAskCase extends UseCaseBase {
  MarkAskCase(
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
    required String beaconId,
    required String title,
    required String targetPersonId,
    String body = '',
    String? linkedMessageId,
    int? staleAfterDays,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw const BeaconCreateException(description: 'Ask title is required');
    }
    if (targetPersonId.trim().isEmpty) {
      throw const BeaconCreateException(
        description: 'Ask target person is required',
      );
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (!beacon.isActive) {
      throw const BeaconCreateException(description: 'Beacon is not open');
    }
    final item = await _itemRepository.create(
      beaconId: beaconId,
      kind: coordinationItemKindAsk,
      creatorId: userId,
      title: trimmed,
      body: body.trim(),
      targetPersonId: targetPersonId,
      linkedMessageId: linkedMessageId,
      staleAfterDays: staleAfterDays,
    );
    final target = item.targetPersonId;
    if (target != null && target.isNotEmpty && target != userId) {
      unawaited(
        _push.notifyNeedsMe(
          beaconId: beaconId,
          actorUserId: userId,
          targetUserId: target,
          excerpt: trimmed.isNotEmpty ? trimmed : body.trim(),
          coordinationItemId: item.id,
        ),
      );
    }
    return item;
  }
}
