import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class UpdateDraftPromiseCase extends UseCaseBase {
  UpdateDraftPromiseCase(
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
    if (body.trim().isEmpty) {
      throw const BeaconCreateException(description: 'Promise body is required');
    }
    final trimmed = title.trim();
    final existing = await _itemRepository.getById(itemId);
    if (existing == null) {
      throw const BeaconCreateException(description: 'Promise not found');
    }
    if (existing.kind != coordinationItemKindPromise) {
      throw const BeaconCreateException(description: 'Item is not a promise');
    }
    if (existing.creatorId != userId) {
      throw const BeaconCreateException(
        description: 'Only the draft author can edit this promise',
      );
    }
    final beacon =
        await _beaconRepository.getBeaconById(beaconId: existing.beaconId);
    if (!beacon.isActive) {
      throw const BeaconCreateException(description: 'Beacon is not open');
    }
    if (updateTargetPersonId) {
      final target = targetPersonId?.trim() ?? '';
      if (target.isNotEmpty && target == userId) {
        throw const BeaconCreateException(
          description: 'Promise cannot target yourself',
        );
      }
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
