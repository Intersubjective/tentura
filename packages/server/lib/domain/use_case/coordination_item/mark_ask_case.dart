import 'package:tentura_server/domain/entity/coordination_item_record.dart';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_port.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class MarkAskCase extends UseCaseBase {
  MarkAskCase(
    this._beaconRepository,
    this._itemRepository,
    BeaconRoomNotificationPort legacyNotificationPort, {
    AttentionIntentCase? attentionIntents,
    TransactionalAttentionCase? attention,
    required super.env,
    required super.logger,
  }) : _attentionIntents = attentionIntents,
       _attention = attention;

  final BeaconRepositoryPort _beaconRepository;
  final CoordinationItemRepositoryPort _itemRepository;
  final AttentionIntentCase? _attentionIntents;
  final TransactionalAttentionCase? _attention;

  Future<CoordinationItemRecord> call({
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
    final target = targetPersonId.trim();
    if (target.isEmpty) {
      throw const BeaconCreateException(
        description: 'Ask target person is required',
      );
    }
    if (target == userId) {
      throw const BeaconCreateException(
        description: 'Ask cannot target yourself',
      );
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (!beacon.allowsCoordination) {
      throw const BeaconCreateException(description: 'Request is not open');
    }
    return _attention!.runAction(
      actorUserId: userId,
      action: (transaction) async {
        final item = await _itemRepository.create(
          beaconId: beaconId,
          kind: coordinationItemKindAsk,
          creatorId: userId,
          title: trimmed,
          body: body.trim(),
          targetPersonId: target,
          linkedMessageId: linkedMessageId,
          staleAfterDays: staleAfterDays,
        );
        final notifyTarget = item.targetPersonId;
        if (notifyTarget != null && notifyTarget.isNotEmpty) {
          await transaction.record(
            await _attentionIntents!.needsMe(
              beaconId: beaconId,
              actorUserId: userId,
              targetUserId: notifyTarget,
              excerpt: trimmed.isNotEmpty ? trimmed : body.trim(),
              coordinationItemId: item.id,
              sourceEventKey: _sourceKey(item, 'created'),
            ),
          );
        }
        return item;
      },
    );
  }

  String _sourceKey(CoordinationItemRecord item, String transition) =>
      'coordination_item:${item.id}:$transition:'
      '${item.updatedAt.toUtc().microsecondsSinceEpoch}';
}
