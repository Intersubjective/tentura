import 'package:tentura_server/domain/entity/coordination_item_record.dart';

import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_port.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import 'coordination_room_access.dart';
import '../_use_case_base.dart';

@Singleton(order: 2)
final class UpdatePlanCase extends UseCaseBase {
  UpdatePlanCase(
    this._beaconRepository,
    this._itemRepository,
    this._room,
    BeaconRoomNotificationPort legacyNotificationPort, {
    AttentionIntentCase? attentionIntents,
    TransactionalAttentionCase? attention,
    required super.env,
    required super.logger,
  }) : _attentionIntents = attentionIntents,
       _attention = attention;

  final BeaconRepositoryPort _beaconRepository;
  final CoordinationItemRepositoryPort _itemRepository;
  final BeaconRoomRepositoryPort _room;
  final AttentionIntentCase? _attentionIntents;
  final TransactionalAttentionCase? _attention;

  Future<CoordinationItemRecord> call({
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
    if (trimmed.length > kBeaconRoomCurrentLineMaxLength) {
      throw BeaconCreateException(
        description:
            'Plan text must be at most $kBeaconRoomCurrentLineMaxLength characters',
      );
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (!beacon.allowsCoordination) {
      throw const BeaconCreateException(description: 'Request is not open');
    }
    await ensureCanCoordinateOnBeacon(
      room: _room,
      beaconId: beaconId,
      userId: userId,
    );
    return _attention!.runAction(
      actorUserId: userId,
      action: (transaction) async {
        final item = await _itemRepository.publishRootPlan(
          beaconId: beaconId,
          creatorId: userId,
          title: trimmed,
          body: body.trim(),
          targetPersonId: targetPersonId,
          linkedMessageId: linkedMessageId,
          syncCurrentLineText: trimmed,
        );
        await transaction.record(
          await _attentionIntents!.coordinationChanged(
            beaconId: beaconId,
            actorUserId: userId,
            planExcerpt: trimmed,
            sourceEventKey: _sourceKey(item, 'plan_updated'),
          ),
        );
        return item;
      },
    );
  }

  String _sourceKey(CoordinationItemRecord item, String transition) =>
      'coordination_item:${item.id}:$transition:'
      '${item.updatedAt.toUtc().microsecondsSinceEpoch}';
}
