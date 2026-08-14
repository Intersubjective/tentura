import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';

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

    test('isolates read-through between two item threads on same beacon', () {
      final tA = DateTime.utc(2026, 1, 2);
      final tB = DateTime.utc(2026, 1, 3);

      store.observeReadThrough('b1', tA, threadId: 'item-a');
      store.observeReadThrough('b1', tB, threadId: 'item-b');

      expect(store.readThrough('b1', threadId: 'item-a'), tA);
      expect(store.readThrough('b1', threadId: 'item-b'), tB);
      expect(store.readThrough('b1'), isNull);
    });

    test('semantic observation is recorded before mark-seen confirmation', () {
      final observed = DateTime.utc(2026, 2, 1);
      store.observeReadThrough('b1', observed, threadId: 'item-a');

      expect(store.readThrough('b1', threadId: 'item-a'), observed);
      expect(store.hasPendingSync('b1', threadId: 'item-a'), isTrue);
      expect(store.syncedAt('b1', threadId: 'item-a'), isNull);
    });

    test('confirmSynced uses persisted response timestamp when local is behind',
        () {
      final observed = DateTime.utc(2026, 2, 1);
      final persisted = DateTime.utc(2026, 2, 1, 12, 30);
      store.observeReadThrough('b1', observed, threadId: 'item-a');

      store.confirmSynced('b1', persisted, threadId: 'item-a');

      expect(store.syncedAt('b1', threadId: 'item-a'), persisted);
      expect(store.readThrough('b1', threadId: 'item-a'), persisted);
      expect(store.hasPendingSync('b1', threadId: 'item-a'), isFalse);
    });

    test('stale persisted response does not regress local read-through', () {
      final local = DateTime.utc(2026, 3, 5);
      final stale = DateTime.utc(2026, 3, 1);
      store.observeReadThrough('b1', local, threadId: 'item-a');

      store.confirmSynced('b1', stale, threadId: 'item-a');

      expect(store.readThrough('b1', threadId: 'item-a'), local);
      expect(store.syncedAt('b1', threadId: 'item-a'), local);
    });

    test('General defaults to general store key', () {
      final t = DateTime.utc(2026, 4, 1);
      store.observeReadThrough('b1', t);

      expect(
        store.readThrough('b1', threadId: RequestThread.generalId),
        t,
      );
    });

    test('threadChanges emits full key; legacy changes is General-only', () async {
      final threadEvents = <RoomReadWatermarkKey>[];
      final legacyEvents = <String>[];
      final threadSub = store.threadChanges.listen(threadEvents.add);
      final legacySub = store.changes.listen(legacyEvents.add);

      store.observeReadThrough(
        'b1',
        DateTime.utc(2026, 5, 1),
        threadId: 'item-a',
      );
      store.observeReadThrough('b1', DateTime.utc(2026, 5, 2));
      await Future<void>.delayed(Duration.zero);

      expect(
        threadEvents,
        [
          const RoomReadWatermarkKey('b1', 'item-a'),
          const RoomReadWatermarkKey('b1', RequestThread.generalId),
        ],
      );
      expect(legacyEvents, ['b1']);

      await threadSub.cancel();
      await legacySub.cancel();
    });
  });
}
