import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_location_maps_uri.dart';
import 'package:tentura/domain/entity/coordinates.dart';

void main() {
  const coords = Coordinates(lat: 52.358, long: 4.881);

  test('builds Android geo URI with coordinates and label', () {
    final uri = beaconLocationMapsUri(
      coordinates: coords,
      label: 'Museumplein 6, Amsterdam',
      platform: BeaconMapsPlatform.android,
    );

    expect(
      uri.toString(),
      'geo:52.358,4.881?q=52.358,4.881(Museumplein%206%2C%20Amsterdam)',
    );
  });

  test('builds iOS Apple Maps URI with coordinates and label', () {
    final uri = beaconLocationMapsUri(
      coordinates: coords,
      label: 'Museumplein 6, Amsterdam',
      platform: BeaconMapsPlatform.ios,
    );

    expect(
      uri.toString(),
      'https://maps.apple.com/?ll=52.358%2C4.881&q=Museumplein+6%2C+Amsterdam',
    );
  });

  test('builds web Google Maps URI from coordinates only', () {
    final uri = beaconLocationMapsUri(
      coordinates: coords,
      label: 'Museumplein 6, Amsterdam',
      platform: BeaconMapsPlatform.web,
    );

    expect(
      uri.toString(),
      'https://www.google.com/maps/search/?api=1&query=52.358%2C4.881',
    );
  });
}
