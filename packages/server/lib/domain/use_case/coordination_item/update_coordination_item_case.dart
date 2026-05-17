import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class UpdateCoordinationItemCase extends UseCaseBase {
  UpdateCoordinationItemCase(
    this._beaconRepository,
    this._itemRepository,
    this._roomRepository, {
    required super.env,
    required super.logger,
  });

  final BeaconRepositoryPort _beaconRepository;
  final CoordinationItemRepositoryPort _itemRepository;
  final BeaconRoomRepository _roomRepository;

  Future<CoordinationItem> call({
    required String userId,
    required String itemId,
    required String title,
    String body = '',
  }) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) {
      throw const BeaconCreateException(description: 'Title is required');
    }
    final existing = await _itemRepository.getById(itemId);
    if (existing == null) {
      throw const IdNotFoundException(description: 'Item not found');
    }
    if (!existing.published) {
      throw const BeaconCreateException(
        description: 'Use updateDraftAsk for unpublished asks',
      );
    }
    if (existing.status != coordinationItemStatusOpen &&
        existing.status != coordinationItemStatusAccepted) {
      throw const BeaconCreateException(description: 'Item is not editable');
    }
    final beacon =
        await _beaconRepository.getBeaconById(beaconId: existing.beaconId);
    if (!beacon.isActive) {
      throw const BeaconCreateException(description: 'Beacon is not open');
    }
    if (!await _canEditItem(
      beaconId: existing.beaconId,
      userId: userId,
      creatorId: existing.creatorId,
    )) {
      throw const UnauthorizedException(
        description: 'Not allowed to edit this item',
      );
    }
    return _itemRepository.updatePublishedItem(
      id: itemId,
      actorId: userId,
      title: trimmed,
      body: body.trim(),
    );
  }

  Future<bool> _canEditItem({
    required String beaconId,
    required String userId,
    required String creatorId,
  }) async {
    if (userId == creatorId) {
      return true;
    }
    if (await _roomRepository.isBeaconAuthor(beaconId: beaconId, userId: userId)) {
      return true;
    }
    if (await _roomRepository.isBeaconSteward(beaconId: beaconId, userId: userId)) {
      return true;
    }
    return false;
  }
}
