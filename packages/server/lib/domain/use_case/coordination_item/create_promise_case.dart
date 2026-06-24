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
final class CreatePromiseCase extends UseCaseBase {
  CreatePromiseCase(
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
    required String beaconId,
    required String title,
    required String targetPersonId,
    String body = '',
    String? linkedMessageId,
    int? staleAfterDays,
  }) async {
    if (body.trim().isEmpty) {
      throw const BeaconCreateException(description: 'Promise body is required');
    }
    final trimmed = title.trim();
    final target = targetPersonId.trim();
    if (target.isEmpty) {
      throw const BeaconCreateException(
        description: 'Promise target person is required',
      );
    }
    if (target == userId) {
      throw const BeaconCreateException(
        description: 'Promise cannot target yourself',
      );
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (!beacon.allowsCoordination) {
      throw const BeaconCreateException(description: 'Beacon is not open');
    }
    final item = await _itemRepository.create(
      beaconId: beaconId,
      kind: coordinationItemKindPromise,
      creatorId: userId,
      title: trimmed,
      body: body.trim(),
      targetPersonId: target,
      linkedMessageId: linkedMessageId,
      staleAfterDays: staleAfterDays,
    );
    unawaited(
      _push.notifyPromiseMade(
        beaconId: beaconId,
        actorUserId: userId,
        excerpt: trimmed.isNotEmpty ? trimmed : body.trim(),
        targetPersonId: target,
        coordinationItemId: item.id,
      ),
    );
    return item;
  }
}
