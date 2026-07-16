import 'package:tentura_server/domain/entity/coordination_item_record.dart';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class PublishDraftBlockerCase extends UseCaseBase {
  PublishDraftBlockerCase(
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
    required String itemId,
    int? staleAfterDays,
  }) async {
    final existing = await _itemRepository.getById(itemId);
    if (existing == null) {
      throw const BeaconCreateException(description: 'Blocker not found');
    }
    if (existing.kind != coordinationItemKindBlocker) {
      throw const BeaconCreateException(
        description: 'Only blockers can be published',
      );
    }
    if (existing.published) {
      throw const BeaconCreateException(
        description: 'This blocker is already live',
      );
    }
    if (existing.creatorId != userId) {
      throw const BeaconCreateException(
        description: 'Only the draft author can publish this blocker',
      );
    }
    final beacon = await _beaconRepository.getBeaconById(
      beaconId: existing.beaconId,
    );
    if (!beacon.allowsCoordination) {
      throw const BeaconCreateException(description: 'Request is not open');
    }
    return _attention!.runAction(
      actorUserId: userId,
      action: (transaction) async {
        final item = await _itemRepository.publishDraftBlocker(
          id: itemId,
          actorId: userId,
          staleAfterDays: staleAfterDays,
        );
        await transaction.record(
          await _attentionIntents!.blockerChanged(
            beaconId: item.beaconId,
            actorUserId: userId,
            excerpt: item.title,
            targetPersonId: item.targetPersonId,
            coordinationItemId: item.id,
            sourceEventKey: _sourceKey(item, 'published'),
            resolved: false,
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
