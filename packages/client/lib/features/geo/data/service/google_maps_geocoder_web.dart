import 'dart:js_interop';

import 'package:tentura/domain/entity/coordinates.dart';

@JS('google.maps.Geocoder')
extension type _JsGeocoder._(JSObject _) implements JSObject {
  external _JsGeocoder();

  external JSPromise<_GeocoderResponse> geocode(JSObject request);
}

extension type _GeocoderResponse._(JSObject _) implements JSObject {
  external JSArray<_GeocoderResult> get results;
}

extension type _GeocoderResult._(JSObject _) implements JSObject {
  @JS('formatted_address')
  external String get formattedAddress;
}

/// Reverse geocodes through the Maps JavaScript SDK already loaded in the
/// page, instead of a raw HTTP call to the classic Geocoding REST API.
///
/// The REST endpoint (`maps.googleapis.com/maps/api/geocode/json`) rejects
/// any HTTP-referrer-restricted key outright ("API keys with referrer
/// restrictions cannot be used with this API"), which is exactly the key
/// type a browser Maps deployment needs. The SDK's own `Geocoder` runs
/// in-browser under that same referrer, so it's accepted.
Future<String?> reverseGeocodeWithJsSdk(Coordinates coordinates) async {
  final request =
      {
            'location': {'lat': coordinates.lat, 'lng': coordinates.long},
          }.jsify()!
          as JSObject;

  try {
    final response = await _JsGeocoder().geocode(request).toDart;
    final results = response.results.toDart;
    return results.isEmpty ? null : results.first.formattedAddress;
  } catch (_) {
    return null;
  }
}
