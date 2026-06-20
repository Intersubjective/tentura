import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class DeleteDraftPromiseCase extends UseCaseBase {
  DeleteDraftPromiseCase(
    this._beaconRepository,
    this._itemRepository, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final CoordinationItemRepositoryPort _itemRepository;

  Future<bool> call({
    required String userId,
    required String itemId,
  }) async {
    final existing = await _itemRepository.getById(itemId);
    if (existing == null) {
      throw const BeaconCreateException(description: 'Promise not found');
    }
    if (existing.kind != coordinationItemKindPromise) {
      throw const BeaconCreateException(description: 'Item is not a promise');
    }
    if (existing.creatorId != userId) {
      throw const BeaconCreateException(
        description: 'Only the draft author can delete this promise',
      );
    }
    final beacon =
        await _beaconRepository.getBeaconById(beaconId: existing.beaconId);
    if (!beacon.allowsCoordination) {
      throw const BeaconCreateException(description: 'Beacon is not open');
    }
    await _itemRepository.deleteDraftAsk(id: itemId, actorId: userId);
    return true;
  }
}
