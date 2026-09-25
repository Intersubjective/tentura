// tentura-fpi landing gate acceptance (chat read receipts / room_seen_peer)

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_seen_peer.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';

void main() {
  group('BeaconRoomInvalidation.fromRealtimeChange', () {
    const beaconId = 'Bseenpeer0001';
    final seenPeer = RealtimeSeenPeer(
      userId: 'Ugggggggggggg',
      lastSeenAt: DateTime.utc(2026, 6, 15, 12),
    );

    test('maps roomSeenPeer change with seenPeer payload', () {
      final change = RealtimeEntityChange(
        kind: RealtimeEntityKind.roomSeenPeer,
        aggregateId: beaconId,
        operation: RealtimeOperation.update,
        source: RealtimeChangeSource.serverInvalidation,
        seenPeer: seenPeer,
      );

      final invalidation = BeaconRoomInvalidation.fromRealtimeChange(change);

      expect(invalidation, isNotNull);
      expect(invalidation!.beaconId, beaconId);
      expect(invalidation.entityType, BeaconRoomEntityType.roomSeenPeer);
      expect(invalidation.seenPeer, seenPeer);
    });

    test('invalidations differing only in seenPeer are not equal', () {
      final first = BeaconRoomInvalidation(
        beaconId: beaconId,
        entityType: BeaconRoomEntityType.roomSeenPeer,
        operation: RealtimeOperation.update,
        seenPeer: RealtimeSeenPeer(
          userId: 'Upeer00000001',
          lastSeenAt: DateTime.utc(2026, 6, 15, 12),
        ),
      );
      final second = BeaconRoomInvalidation(
        beaconId: beaconId,
        entityType: BeaconRoomEntityType.roomSeenPeer,
        operation: RealtimeOperation.update,
        seenPeer: RealtimeSeenPeer(
          userId: 'Upeer00000002',
          lastSeenAt: DateTime.utc(2026, 6, 15, 12),
        ),
      );

      expect(first, isNot(equals(second)));
    });
  });
}
