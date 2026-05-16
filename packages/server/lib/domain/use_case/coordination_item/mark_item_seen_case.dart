import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_item_repository_port.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';

import '../_use_case_base.dart';

@Singleton(order: 2)
final class MarkItemSeenCase extends UseCaseBase {
  MarkItemSeenCase(
    this._itemRepository,
    this._roomRepository, {
    required super.env,
    required super.logger,
  });

  final CoordinationItemRepositoryPort _itemRepository;
  final BeaconRoomRepository _roomRepository;

  Future<bool> call({
    required String userId,
    required String itemId,
  }) async {
    final item = await _itemRepository.getById(itemId);
    if (item == null) {
      throw const IdNotFoundException(description: 'Item not found');
    }
    final allowed = await _canUseRoom(
      beaconId: item.beaconId,
      userId: userId,
    );
    if (!allowed) {
      throw const UnauthorizedException(
        description: 'Room access required',
      );
    }
    await _itemRepository.markItemSeen(
      userId: userId,
      itemId: itemId,
      at: DateTime.timestamp(),
    );
    return true;
  }

  Future<bool> _canUseRoom({
    required String beaconId,
    required String userId,
  }) async {
    if (await _roomRepository.isBeaconAuthor(beaconId: beaconId, userId: userId)) {
      return true;
    }
    if (await _roomRepository.isBeaconSteward(beaconId: beaconId, userId: userId)) {
      return true;
    }
    final p = await _roomRepository.findParticipant(
      beaconId: beaconId,
      userId: userId,
    );
    return p?.roomAccess == RoomAccessBits.admitted;
  }
}
