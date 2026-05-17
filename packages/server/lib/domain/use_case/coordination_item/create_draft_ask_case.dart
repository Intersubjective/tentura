import 'package:injectable/injectable.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class CreateDraftAskCase extends UseCaseBase {
  CreateDraftAskCase(
    this._beaconRepository,
    this._itemRepository, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final CoordinationItemRepositoryPort _itemRepository;

  Future<CoordinationItem> call({
    required String userId,
    required String beaconId,
    required String title,
    String body = '',
    String? targetPersonId,
    String? linkedMessageId,
  }) async {
    if (body.trim().isEmpty) {
      throw const BeaconCreateException(description: 'Ask body is required');
    }
    final trimmed = title.trim();
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (!beacon.isActive) {
      throw const BeaconCreateException(description: 'Beacon is not open');
    }
    if (beacon.author.id != userId) {
      throw const BeaconCreateException(
        description: 'Only the beacon owner can prepare asks',
      );
    }
    final target = targetPersonId?.trim();
    return _itemRepository.createDraftAsk(
      beaconId: beaconId,
      creatorId: userId,
      title: trimmed,
      body: body.trim(),
      targetPersonId:
          target == null || target.isEmpty ? null : target,
      linkedMessageId: linkedMessageId,
    );
  }
}
