import 'package:injectable/injectable.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class UpdateDraftAskCase extends UseCaseBase {
  UpdateDraftAskCase(
    this._beaconRepository,
    this._itemRepository, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final CoordinationItemRepositoryPort _itemRepository;

  Future<CoordinationItem> call({
    required String userId,
    required String itemId,
    required String title,
    String body = '',
    bool updateTargetPersonId = false,
    String? targetPersonId,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw const BeaconCreateException(description: 'Ask title is required');
    }
    final existing = await _itemRepository.getById(itemId);
    if (existing == null) {
      throw const BeaconCreateException(description: 'Ask not found');
    }
    if (existing.creatorId != userId) {
      throw const BeaconCreateException(
        description: 'Only the draft author can edit this ask',
      );
    }
    final beacon =
        await _beaconRepository.getBeaconById(beaconId: existing.beaconId);
    if (!beacon.isActive) {
      throw const BeaconCreateException(description: 'Beacon is not open');
    }
    return _itemRepository.updateDraftAsk(
      id: itemId,
      actorId: userId,
      title: trimmed,
      body: body.trim(),
      updateTargetPersonId: updateTargetPersonId,
      targetPersonId: targetPersonId,
    );
  }
}
