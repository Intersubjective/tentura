import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class CreateResolutionCase extends UseCaseBase {
  CreateResolutionCase(
    this._beaconRepository,
    this._itemRepository, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final CoordinationItemRepositoryPort _itemRepository;

  Future<CoordinationItemRecord> call({
    required String userId,
    required String beaconId,
    required String title,
    String body = '',
    String? targetItemId,
    String? targetMessageId,
    String? linkedMessageId,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw const BeaconCreateException(description: 'Resolution title is required');
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (!beacon.allowsCoordination) {
      throw const BeaconCreateException(description: 'Beacon is not open');
    }
    return _itemRepository.create(
      beaconId: beaconId,
      kind: coordinationItemKindResolution,
      creatorId: userId,
      title: trimmed,
      body: body.trim(),
      targetItemId: targetItemId,
      targetMessageId: targetMessageId,
      linkedMessageId: linkedMessageId,
    );
  }
}
