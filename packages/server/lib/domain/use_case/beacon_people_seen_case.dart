import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_people_seen_repository_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class BeaconPeopleSeenCase extends UseCaseBase {
  BeaconPeopleSeenCase(
    this._room,
    this._peopleSeen, {
    required super.env,
    required super.logger,
  });

  final BeaconRoomRepositoryPort _room;

  final BeaconPeopleSeenRepositoryPort _peopleSeen;

  Future<Map<String, Object?>> markPeopleSeen({
    required String beaconId,
    required String userId,
    String? readThroughAtIso,
  }) async {
    final isModerator =
        await _room.isBeaconAuthor(beaconId: beaconId, userId: userId) ||
        await _room.isBeaconSteward(beaconId: beaconId, userId: userId);
    if (!isModerator) {
      throw const UnauthorizedException(description: 'Author or steward only');
    }
    final now = DateTime.timestamp();
    final raw = readThroughAtIso?.trim();
    final parsed = raw == null || raw.isEmpty ? null : DateTime.tryParse(raw);
    final at = parsed == null || parsed.isAfter(now) ? now : parsed;
    final persistedAt = await _peopleSeen.markSeen(
      userId: userId,
      beaconId: beaconId,
      at: at,
    );
    return {
      'beaconId': beaconId,
      'seenAt': persistedAt.toUtc().toIso8601String(),
    };
  }
}
