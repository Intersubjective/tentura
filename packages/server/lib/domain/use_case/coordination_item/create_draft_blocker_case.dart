import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/coordination_item_record.dart';

import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../_use_case_base.dart';
import 'coordination_room_access.dart';

@Singleton(order: 2)
final class CreateDraftBlockerCase extends UseCaseBase {
  CreateDraftBlockerCase(
    this._beaconRepository,
    this._itemRepository,
    this._room, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final CoordinationItemRepositoryPort _itemRepository;
  final BeaconRoomRepositoryPort _room;

  Future<CoordinationItemRecord> call({
    required String userId,
    required String beaconId,
    required String title,
    String body = '',
    String? targetPersonId,
    int? staleAfterDays,
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw const BeaconCreateException(description: 'Blocker title is required');
    }
    final beacon = await _beaconRepository.getBeaconById(beaconId: beaconId);
    if (!beacon.allowsCoordination) {
      throw const BeaconCreateException(description: 'Beacon is not open');
    }
    await ensureCanCoordinateOnBeacon(
      room: _room,
      beaconId: beaconId,
      userId: userId,
    );
    final target = targetPersonId?.trim();
    return _itemRepository.createDraftBlocker(
      beaconId: beaconId,
      creatorId: userId,
      title: trimmed,
      body: body.trim(),
      targetPersonId:
          target == null || target.isEmpty ? null : target,
      staleAfterDays: staleAfterDays,
    );
  }
}
