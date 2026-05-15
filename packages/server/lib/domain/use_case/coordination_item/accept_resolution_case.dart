import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class AcceptResolutionCase extends UseCaseBase {
  AcceptResolutionCase(
    this._itemRepository, {
    required super.env,
    required super.logger,
  });

  final CoordinationItemRepositoryPort _itemRepository;

  Future<CoordinationItem> call({
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
    if (targetId != null && targetId.isNotEmpty) {
      final target = await _itemRepository.getById(targetId);
      if (target != null &&
          (target.status == coordinationItemStatusOpen ||
              target.status == coordinationItemStatusAccepted)) {
        await _itemRepository.updateStatus(
          id: targetId,
          newStatus: coordinationItemStatusResolved,
          actorId: userId,
        );
      }
    }

    return _itemRepository.updateStatus(
      id: itemId,
      newStatus: coordinationItemStatusResolved,
      actorId: userId,
    );
  }
}
