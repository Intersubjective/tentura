import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class RedirectAskCase extends UseCaseBase {
  RedirectAskCase(
    this._itemRepository, {
    required super.env,
    required super.logger,
  });

  final CoordinationItemRepositoryPort _itemRepository;

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
    return _itemRepository.redirectTarget(
      id: itemId,
      actorId: userId,
      newTargetPersonId: target,
    );
  }
}
