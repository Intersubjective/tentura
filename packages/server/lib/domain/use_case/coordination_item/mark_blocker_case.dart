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
final class MarkBlockerCase extends UseCaseBase {
  MarkBlockerCase(
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
    String body = '',
    String? targetPersonId,
    String? linkedMessageId,
    int? staleAfterDays,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw const BeaconCreateException(description: 'Blocker title is required');
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (!beacon.allowsCoordination) {
      throw const BeaconCreateException(
        description: 'Request is not open',
      );
    }
    final item = await _itemRepository.create(
      beaconId: beaconId,
      kind: coordinationItemKindBlocker,
      creatorId: userId,
      title: trimmed,
      body: body.trim(),
      targetPersonId: targetPersonId,
      linkedMessageId: linkedMessageId,
      staleAfterDays: staleAfterDays,
    );
    unawaited(
      _push.notifyBlockerOpened(
        beaconId: beaconId,
        actorUserId: userId,
        excerpt: trimmed,
        targetPersonId: targetPersonId,
        coordinationItemId: item.id,
      ),
    );
    return item;
  }
}
