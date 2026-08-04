import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class AcceptPromiseCase extends UseCaseBase {
  AcceptPromiseCase(
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
  }) async {
    final item = await _itemRepository.getById(itemId);
    if (item == null) {
      throw const IdNotFoundException(description: 'Promise not found');
    }
    if (item.kind != coordinationItemKindPromise) {
      throw const BeaconCreateException(description: 'Item is not a promise');
    }
    if (item.status != coordinationItemStatusOpen) {
      throw const BeaconCreateException(description: 'Promise is not open');
    }
    if (item.targetPersonId != userId) {
      throw const BeaconCreateException(
        description: 'Only the recipient can accept this promise',
      );
    }
    return _attention!.runAction(
      actorUserId: userId,
      action: (transaction) async {
        final updated = await _itemRepository.acceptItem(
          id: itemId,
          actorId: userId,
          acceptedById: userId,
        );
        await transaction.record(
          await _attentionIntents!.commitmentChanged(
            beaconId: updated.beaconId,
            actorUserId: userId,
            transition: 'accepted',
            excerpt: updated.title,
            targetPersonId: updated.creatorId,
            coordinationItemId: updated.id,
            sourceEventKey: _sourceKey(updated, 'accepted'),
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
