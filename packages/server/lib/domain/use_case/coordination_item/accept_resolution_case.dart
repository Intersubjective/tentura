import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class AcceptResolutionCase extends UseCaseBase {
  AcceptResolutionCase(
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

    final targetId = resolution.targetItemId;
    CoordinationItemRecord? target;
    if (targetId != null && targetId.isNotEmpty) {
      target = await _itemRepository.getById(targetId);
    }

    return _attention!.runAction(
      actorUserId: userId,
      action: (transaction) async {
        if (target != null &&
            (target.status == coordinationItemStatusOpen ||
                target.status == coordinationItemStatusAccepted)) {
          await _itemRepository.updateStatus(
            id: targetId!,
            newStatus: coordinationItemStatusResolved,
            actorId: userId,
          );
        }

        final updatedResolution = await _itemRepository.updateStatus(
          id: itemId,
          newStatus: coordinationItemStatusResolved,
          actorId: userId,
        );

        final resolutionCreatorId = updatedResolution.creatorId;
        if (resolutionCreatorId.isNotEmpty) {
          await transaction.record(
            await _attentionIntents!.commitmentChanged(
              beaconId: updatedResolution.beaconId,
              actorUserId: userId,
              transition: 'resolved',
              excerpt: updatedResolution.title,
              targetPersonId: resolutionCreatorId,
              coordinationItemId: updatedResolution.id,
              creatorId: target?.creatorId,
              sourceEventKey: _sourceKey(updatedResolution, 'resolution_accepted'),
            ),
          );
        }

        return updatedResolution;
      },
    );
  }

  String _sourceKey(CoordinationItemRecord item, String transition) =>
      'coordination_item:${item.id}:$transition:'
      '${item.updatedAt.toUtc().microsecondsSinceEpoch}';
}
