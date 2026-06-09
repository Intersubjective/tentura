import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_room/domain/room_read_watermark_store.dart';

void main() {
  group('shell badge derives from watermark', () {
    test('resolveUnread zeros stale server count after local read-through', () {
      final store = RoomReadWatermarkStore.testing();
      addTearDown(store.dispose);

      final serverSeen = DateTime.utc(2026, 1, 1);
      final readThrough = DateTime.utc(2026, 1, 5);
      store.observeReadThrough('b1', readThrough);

      expect(
        store.resolveUnread(
          beaconId: 'b1',
          serverCount: 4,
          serverSeenAt: serverSeen,
        ),
        0,
        reason: 'shell badge should read 0 after user read through bottom',
      );
    });
  });
}
