import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/beacon/beacon_surface.dart';

void main() {
  test('help_offers deep link opens People (issue #147)', () {
    expect(beaconViewSurfaceForTab(kBeaconViewTabPeople), BeaconSurface.people);
    expect(
      beaconViewSurfaceForTab(kBeaconViewTabHelpOffers),
      BeaconSurface.people,
    );
    expect(beaconViewSurfaceForTab(kBeaconViewTabNow), BeaconSurface.now);
    expect(beaconViewSurfaceForTab('log'), BeaconSurface.now);
    expect(beaconViewSurfaceForTab(kBeaconViewTabThreads), BeaconSurface.room);
  });
}
