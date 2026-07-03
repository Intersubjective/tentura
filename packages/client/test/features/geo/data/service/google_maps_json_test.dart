import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/geo/data/service/google_maps_json.dart';

void main() {
  group('googleMapsApiErrorMessage', () {
    test('reads Places API error envelope', () {
      expect(
        googleMapsApiErrorMessage(
          '{"error":{"message":"Places API (New) has not been enabled.","status":"PERMISSION_DENIED"}}',
        ),
        'Places API (New) has not been enabled.',
      );
    });

    test('reads classic Geocoding status errors', () {
      expect(
        googleMapsApiErrorMessage(
          '{"status":"REQUEST_DENIED","error_message":"The provided API key is invalid."}',
        ),
        'The provided API key is invalid.',
      );
    });
  });

  group('readGoogleMapsJsonList', () {
    test('returns empty list for map values', () {
      expect(readGoogleMapsJsonList({'unexpected': true}), isEmpty);
    });
  });
}
