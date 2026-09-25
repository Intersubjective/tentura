import 'package:test/test.dart';
import 'package:tentura_server/domain/entity/beacon_fact_room_access.dart';

/// tentura-617.4 — plan §14.2: Freezed
/// `BeaconFactRoomAccess(beaconStatus, canUseRoom, canReadContent, exists)`.
void main() {
  test('carries preflight access flags', () {
    const access = BeaconFactRoomAccess(
      beaconStatus: 2,
      canUseRoom: true,
      canReadContent: false,
      exists: true,
    );
    expect(access.beaconStatus, 2);
    expect(access.canUseRoom, isTrue);
    expect(access.canReadContent, isFalse);
    expect(access.exists, isTrue);
  });

  test('value equality and copyWith', () {
    const a = BeaconFactRoomAccess(
      beaconStatus: 0,
      canUseRoom: true,
      canReadContent: true,
      exists: true,
    );
    expect(
      a,
      const BeaconFactRoomAccess(
        beaconStatus: 0,
        canUseRoom: true,
        canReadContent: true,
        exists: true,
      ),
    );
    expect(a.copyWith(exists: false).exists, isFalse);
  });
}
