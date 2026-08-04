import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class RejectResolutionCase extends UseCaseBase {
  RejectResolutionCase(
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
    String? reason,
  }) async {
    final resolution = await _itemRepository.getById(itemId);
    if (resolution == null) {
      throw const BeaconCreateException(description: 'Resolution not found');
    }
    if (resolution.kind != coordinationItemKindResolution) {
      throw const BeaconCreateException(description: 'Not a resolution item');
    }
    if (resolution.status != coordinationItemStatusOpen) {
      throw const BeaconCreateException(description: 'Resolution is not open');
    }
    return _attention!.runAction(
      actorUserId: userId,
      action: (transaction) async {
        final updated = await _itemRepository.updateStatus(
          id: itemId,
          newStatus: coordinationItemStatusCancelled,
          actorId: userId,
        );
        final resolutionCreatorId = updated.creatorId;
        if (resolutionCreatorId.isNotEmpty) {
          await transaction.record(
            await _attentionIntents!.commitmentChanged(
              beaconId: updated.beaconId,
              actorUserId: userId,
              transition: 'cancelled',
              excerpt: updated.title,
              targetPersonId: resolutionCreatorId,
              coordinationItemId: updated.id,
              sourceEventKey: _sourceKey(updated, 'resolution_rejected'),
            ),
          );
        }
        return updated;
      },
    );
  }

  String _sourceKey(CoordinationItemRecord item, String transition) =>
      'coordination_item:${item.id}:$transition:'
      '${item.updatedAt.toUtc().microsecondsSinceEpoch}';
}
