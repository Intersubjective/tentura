import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class AddPlanStepCase extends UseCaseBase {
  AddPlanStepCase(
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
    required String parentItemId,
    required String title,
    String body = '',
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw const BeaconCreateException(description: 'Step title is required');
    }
    final parent = await _itemRepository.getById(parentItemId);
    if (parent == null) {
      throw const BeaconCreateException(description: 'Plan not found');
    }
    if (parent.kind != coordinationItemKindPlan) {
      throw const BeaconCreateException(description: 'Parent is not a plan');
    }
    return _attention!.runAction(
      actorUserId: userId,
      action: (transaction) async {
        final step = await _itemRepository.addPlanStep(
          parentItemId: parentItemId,
          creatorId: userId,
          title: trimmed,
          body: body.trim(),
        );
        await transaction.record(
          await _attentionIntents!.coordinationChanged(
            beaconId: step.beaconId,
            actorUserId: userId,
            planExcerpt: trimmed,
            sourceEventKey: _sourceKey(step, 'plan_step_added'),
          ),
        );
        return step;
      },
    );
  }

  String _sourceKey(CoordinationItemRecord item, String transition) =>
      'coordination_item:${item.id}:$transition:'
      '${item.updatedAt.toUtc().microsecondsSinceEpoch}';
}
