import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_room/domain/beacon_room_local_change_bus.dart';
import 'package:tentura/features/beacon_room/domain/entity/beacon_room_invalidation.dart';

void main() {
  test('emits invalidation-shaped local room changes', () async {
    final bus = BeaconRoomLocalChangeBus();
    addTearDown(bus.dispose);
    final events = <BeaconRoomInvalidation>[];
    final sub = bus.changes.listen(events.add);
    addTearDown(sub.cancel);

    bus.notifyBeaconChanged(
      beaconId: 'b-local',
      entityType: BeaconRoomEntityType.coordinationItem,
    );
    await Future<void>.delayed(Duration.zero);

    expect(events, [
      const BeaconRoomInvalidation(
        beaconId: 'b-local',
        entityType: BeaconRoomEntityType.coordinationItem,
      ),
    ]);
  });
}
