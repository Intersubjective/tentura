import 'package:test/test.dart';

import 'package:tentura_server/domain/beacon_lineage_visibility.dart';
import 'package:tentura_server/domain/exception.dart';

import '../support/fake_beacon_access_guard.dart';

void main() {
  group('assertBeaconLineageSourceVisible', () {
    test('passes when guard allows content read', () async {
      final guard = FakeBeaconAccessGuard(contentAllowed: true);
      await expectLater(
        assertBeaconLineageSourceVisible(
          guard: guard,
          beaconId: 'B1',
          userId: 'Uauth',
        ),
        completes,
      );
    });

    test('throws when guard denies content read', () async {
      final guard = FakeBeaconAccessGuard(contentAllowed: false);
      await expectLater(
        assertBeaconLineageSourceVisible(
          guard: guard,
          beaconId: 'B1',
          userId: 'Uauth',
        ),
        throwsA(isA<BeaconCreateException>()),
      );
    });
  });
}
