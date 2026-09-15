import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/policy/beacon_room_lifecycle_write_policy.dart';
import 'package:test/test.dart';

void main() {
  group('BeaconRoomLifecycleWritePolicy', () {
    test('blocksOrdinaryUserWrites mirrors !allowsDiscussionWrites', () {
      for (final status in BeaconStatus.values) {
        expect(
          BeaconRoomLifecycleWritePolicy.blocksOrdinaryUserWrites(status),
          !status.allowsDiscussionWrites,
          reason: '$status',
        );
      }
    });
  });
}
