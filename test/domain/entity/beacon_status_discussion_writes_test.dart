import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:test/test.dart';

void main() {
  group('BeaconStatus.allowsDiscussionWrites', () {
    test('writable for open-family, draft, and wrapping-up', () {
      for (final status in [
        BeaconStatus.open,
        BeaconStatus.needsMoreHelp,
        BeaconStatus.enoughHelp,
        BeaconStatus.draft,
        BeaconStatus.reviewOpen,
      ]) {
        expect(
          status.allowsDiscussionWrites,
          isTrue,
          reason: '$status',
        );
      }
    });

    test('locked for closed, cancelled, and deleted', () {
      for (final status in [
        BeaconStatus.closed,
        BeaconStatus.cancelled,
        BeaconStatus.deleted,
      ]) {
        expect(
          status.allowsDiscussionWrites,
          isFalse,
          reason: '$status',
        );
      }
    });
  });
}
