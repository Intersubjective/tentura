import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/remote_api_client/build_client.dart';

void main() {
  group('direct V2 operation routing', () {
    test('BeaconStageImage and BeaconSetMedia are routed to Tentura V2', () {
      expect(isTenturaDirectOperation('BeaconStageImage'), isTrue);
      expect(isTenturaDirectOperation('BeaconSetMedia'), isTrue);
      expect(isTenturaDirectOperation('BeaconAddImage'), isTrue);
    });

    test('beaconSetCover is not a supported operation name', () {
      expect(isTenturaDirectOperation('BeaconSetCover'), isFalse);
      expect(isTenturaDirectOperation('beaconSetCover'), isFalse);
    });
  });
}
