import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class ResolveAskCase extends UseCaseBase {
  ResolveAskCase(
    this._itemRepository, {
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
      throw const IdNotFoundException(description: 'Ask not found');
    }
    if (item.kind != coordinationItemKindAsk) {
      throw const BeaconCreateException(description: 'Item is not an ask');
    }
    if (item.status != coordinationItemStatusOpen &&
        item.status != coordinationItemStatusAccepted) {
      throw const BeaconCreateException(description: 'Ask cannot be resolved');
    }
    return _attention!.runAction(
      actorUserId: userId,
      action: (transaction) async {
        final updated = await _itemRepository.updateStatus(
          id: itemId,
          newStatus: coordinationItemStatusResolved,
          actorId: userId,
        );
        final counterpart = _counterpart(updated, userId);
        if (counterpart != null) {
          await transaction.record(
            await _attentionIntents!.commitmentChanged(
              beaconId: updated.beaconId,
              actorUserId: userId,
              transition: 'resolved',
              excerpt: updated.title,
              targetPersonId: counterpart,
              coordinationItemId: updated.id,
              coordinationItemKind: updated.kind,
              sourceEventKey: _sourceKey(updated, 'resolved'),
            ),
          );
        }
        return updated;
      },
    );
  }

  String? _counterpart(CoordinationItemRecord item, String actorId) {
    if (actorId == item.creatorId) {
      return item.targetPersonId;
    }
    return item.creatorId;
  }

  String _sourceKey(CoordinationItemRecord item, String transition) =>
      'coordination_item:${item.id}:$transition:'
      '${item.updatedAt.toUtc().microsecondsSinceEpoch}';
}
