import 'package:tentura_server/domain/entity/coordination_item_record.dart';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class ResolveBlockerCase extends UseCaseBase {
  ResolveBlockerCase(
    this._itemRepository,
    BeaconRoomNotificationPort legacyNotificationPort, {
    AttentionIntentCase? attentionIntents,
    TransactionalAttentionCase? attention,
    required super.env,
    required super.logger,
  }) : _attentionIntents = attentionIntents,
       _attention = attention;

  final CoordinationItemRepositoryPort _itemRepository;
  final AttentionIntentCase? _attentionIntents;
  final TransactionalAttentionCase? _attention;

  Future<CoordinationItemRecord> call({
    required String userId,
    required String itemId,
    String note = '',
  }) async {
    final item = await _itemRepository.getById(itemId);
    if (item == null) {
      throw const IdNotFoundException(description: 'Blocker not found');
    }
    if (item.kind != coordinationItemKindBlocker) {
      throw const BeaconCreateException(description: 'Item is not a blocker');
    }
    if (item.status != coordinationItemStatusOpen) {
      throw const BeaconCreateException(description: 'Blocker is not open');
    }
    return _attention!.runAction(
      actorUserId: userId,
      action: (transaction) async {
        final updated = await _itemRepository.updateStatus(
          id: itemId,
          newStatus: coordinationItemStatusResolved,
          actorId: userId,
        );
        await transaction.record(
          await _attentionIntents!.blockerChanged(
            beaconId: updated.beaconId,
            actorUserId: userId,
            excerpt: updated.title,
            targetPersonId: updated.targetPersonId,
            coordinationItemId: updated.id,
            sourceEventKey: _sourceKey(updated, 'resolved'),
            resolved: true,
          ),
        );
        return updated;
      },
    );
  }

  String _sourceKey(CoordinationItemRecord item, String transition) =>
      'coordination_item:${item.id}:$transition:'
      '${item.updatedAt.toUtc().microsecondsSinceEpoch}';
}
