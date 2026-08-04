import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/domain/port/user_block_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class RedirectAskCase extends UseCaseBase {
  RedirectAskCase(
    this._itemRepository,
    this._userBlockRepository, {
    AttentionIntentCase? attentionIntents,
    TransactionalAttentionCase? attention,
    required super.env,
    required super.logger,
  }) : _attentionIntents = attentionIntents,
       _attention = attention;

  final CoordinationItemRepositoryPort _itemRepository;
  final UserBlockRepositoryPort _userBlockRepository;
  final AttentionIntentCase? _attentionIntents;
  final TransactionalAttentionCase? _attention;

  Future<CoordinationItemRecord> call({
    required String userId,
    required String itemId,
    required String newTargetPersonId,
  }) async {
    final item = await _itemRepository.getById(itemId);
    if (item == null) {
      throw const IdNotFoundException(description: 'Ask not found');
    }
    if (item.kind != coordinationItemKindAsk) {
      throw const BeaconCreateException(description: 'Item is not an ask');
    }
    if (item.status != coordinationItemStatusOpen) {
      throw const BeaconCreateException(description: 'Ask is not open');
    }
    final target = newTargetPersonId.trim();
    if (target.isEmpty) {
      throw const BeaconCreateException(
        description: 'New target person is required',
      );
    }
    if (target == userId) {
      throw const BeaconCreateException(
        description: 'Ask cannot target yourself',
      );
    }
    if (await _userBlockRepository.isBlockedPair(a: userId, b: target)) {
      throw const UnauthorizedException(
        description: 'Cannot assign coordination item to a blocked user',
      );
    }
    final previousTarget = item.targetPersonId;
    return _attention!.runAction(
      actorUserId: userId,
      action: (transaction) async {
        final updated = await _itemRepository.redirectTarget(
          id: itemId,
          actorId: userId,
          newTargetPersonId: target,
        );
        await transaction.record(
          await _attentionIntents!.commitmentChanged(
            beaconId: updated.beaconId,
            actorUserId: userId,
            transition: 'redirected_to',
            excerpt: updated.title,
            targetPersonId: updated.targetPersonId,
            coordinationItemId: updated.id,
            sourceEventKey: _sourceKey(updated, 'redirected_to'),
          ),
        );
        if (previousTarget != null &&
            previousTarget.isNotEmpty &&
            previousTarget != updated.targetPersonId) {
          await transaction.record(
            await _attentionIntents!.commitmentChanged(
              beaconId: updated.beaconId,
              actorUserId: userId,
              transition: 'redirected_from',
              excerpt: updated.title,
              targetPersonId: previousTarget,
              coordinationItemId: updated.id,
              sourceEventKey: _sourceKey(updated, 'redirected_from'),
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
