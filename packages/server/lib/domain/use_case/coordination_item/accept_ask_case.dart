import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class AcceptAskCase extends UseCaseBase {
  AcceptAskCase(
    this._itemRepository, {
    required super.env,
    required super.logger,
  });

  final CoordinationItemRepositoryPort _itemRepository;

  Future<CoordinationItemRecord> call({
    required String userId,
    required String itemId,
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
    return _itemRepository.acceptItem(
      id: itemId,
      actorId: userId,
      acceptedById: userId,
    );
  }
}
