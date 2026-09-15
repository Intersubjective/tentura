import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_constants.dart';

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
