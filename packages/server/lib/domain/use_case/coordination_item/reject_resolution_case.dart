import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class RejectResolutionCase extends UseCaseBase {
  RejectResolutionCase(
    this._itemRepository, {
    required super.env,
    required super.logger,
  });

  final CoordinationItemRepositoryPort _itemRepository;

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
    return _itemRepository.updateStatus(
      id: itemId,
      newStatus: coordinationItemStatusCancelled,
      actorId: userId,
    );
  }
}
