import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_room/domain/room_read_watermark_store.dart';

void main() {
  group('RoomReadWatermarkStore', () {
    late RoomReadWatermarkStore store;

    setUp(() {
      store = RoomReadWatermarkStore.testing();
    });

    tearDown(() => store.dispose());

    test('observeReadThrough is monotonic', () {
      final t1 = DateTime.utc(2026);
      final t2 = DateTime.utc(2026, 1, 2);

      expect(store.observeReadThrough('b1', t1), isTrue);
      expect(store.readThrough('b1'), t1);
      expect(store.observeReadThrough('b1', t1), isFalse);
      expect(store.observeReadThrough('b1', t2), isTrue);
      expect(store.readThrough('b1'), t2);
    });

    test('confirmSynced never regresses below local read-through', () {
      final local = DateTime.utc(2026, 1, 5);
      final server = DateTime.utc(2026, 1, 3);
      store.observeReadThrough('b1', local);
      store.confirmSynced('b1', server);
      expect(store.readThrough('b1'), local);
      expect(store.syncedAt('b1'), local);
      expect(store.hasPendingSync('b1'), isFalse);
    });

    test('hasPendingSync when local ahead of synced', () {
      final t1 = DateTime.utc(2026);
      final t2 = DateTime.utc(2026, 1, 2);
      store.observeReadThrough('b1', t2);
      expect(store.hasPendingSync('b1'), isTrue);
      store.confirmSynced('b1', t1);
      expect(store.hasPendingSync('b1'), isFalse);
    });

    test('resolveUnread matrix', () {
      final local = DateTime.utc(2026, 1, 5);
      final staleSeen = DateTime.utc(2026);
      final freshSeen = DateTime.utc(2026, 1, 6);

      expect(
        store.resolveUnread(
          beaconId: 'b1',
          serverCount: 0,
          serverSeenAt: staleSeen,
        ),
        0,
      );

      store.observeReadThrough('b1', local);
      expect(
        store.resolveUnread(
          beaconId: 'b1',
          serverCount: 3,
          serverSeenAt: staleSeen,
        ),
        0,
      );
      expect(
        store.resolveUnread(
          beaconId: 'b1',
          serverCount: 3,
          serverSeenAt: null,
        ),
        0,
      );
      expect(
        store.resolveUnread(
          beaconId: 'b1',
          serverCount: 3,
          serverSeenAt: freshSeen,
        ),
        3,
      );
    });

    test('changes stream emits beacon id on updates', () async {
      final events = <String>[];
      final sub = store.changes.listen(events.add);
      store.observeReadThrough('b1', DateTime.utc(2026));
      await Future<void>.delayed(Duration.zero);
      expect(events, ['b1']);
      await sub.cancel();
    });
  });
}
