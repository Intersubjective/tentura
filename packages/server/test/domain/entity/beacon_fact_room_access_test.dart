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
      kind: 0,
      isDraft: false,
      isExpiredPost: false,
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
      kind: 0,
      isDraft: false,
      isExpiredPost: false,
    );
    expect(
      a,
      const BeaconFactRoomAccess(
        beaconStatus: 0,
        canUseRoom: true,
        canReadContent: true,
        exists: true,
        kind: 0,
        isDraft: false,
        isExpiredPost: false,
      ),
    );
    expect(a.copyWith(exists: false).exists, isFalse);
  });

  group('beacon kind, draft and expired-Post flags', () {
    const base = BeaconFactRoomAccess(
      beaconStatus: 0,
      canUseRoom: true,
      canReadContent: true,
      exists: true,
      kind: 1,
      isDraft: true,
      isExpiredPost: true,
    );

    test('are carried as given', () {
      expect(base.kind, 1);
      expect(base.isDraft, isTrue);
      expect(base.isExpiredPost, isTrue);
    });

    test('instances differing in one flag are not equal', () {
      expect(base.copyWith(kind: 0), isNot(base));
      expect(base.copyWith(isDraft: false), isNot(base));
      expect(base.copyWith(isExpiredPost: false), isNot(base));
      expect(base.copyWith(), base);
    });

    test('copyWith(isDraft: true) sets the draft flag', () {
      final open = base.copyWith(isDraft: false);
      expect(open.isDraft, isFalse);
      expect(open.copyWith(isDraft: true).isDraft, isTrue);
    });
  });
}
