import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/remote_api_client/build_client.dart';

void main() {
  group('beacon hierarchy direct V2 operation routing', () {
    test('all five hierarchy client documents route to Tentura V2', () {
      const operationNames = [
        'BeaconHierarchyCapabilities',
        'BeaconChildren',
        'BeaconParentReference',
        'BeaconPromotionSource',
        'BeaconChildCreate',
      ];
      for (final name in operationNames) {
        expect(isTenturaDirectOperation(name), isTrue, reason: name);
      }
    });

    test('an unrelated Hasura-only operation name is not routed to V2', () {
      expect(isTenturaDirectOperation('BeaconFetchById'), isFalse);
      expect(isTenturaDirectOperation('beaconChildren'), isFalse);
    });
  });
}
