import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:test/test.dart';

void main() {
  group('BeaconStatus.allowsEdit', () {
    test('editable for open-family and wrapping-up', () {
      for (final status in [
        BeaconStatus.open,
        BeaconStatus.needsMoreHelp,
        BeaconStatus.enoughHelp,
        BeaconStatus.reviewOpen,
      ]) {
        expect(status.allowsEdit, isTrue, reason: '$status');
      }
    });

    test('not editable for draft, closed, cancelled and deleted', () {
      for (final status in [
        BeaconStatus.draft,
        BeaconStatus.closed,
        BeaconStatus.cancelled,
        BeaconStatus.deleted,
      ]) {
        expect(status.allowsEdit, isFalse, reason: '$status');
      }
    });
  });
}
