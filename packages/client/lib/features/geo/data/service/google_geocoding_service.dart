import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/env.dart';

import 'google_maps_geocoder.dart';
import 'google_maps_json.dart';

@lazySingleton
class GoogleGeocodingService {
  GoogleGeocodingService(Env env) : this.withClient(env, client: http.Client());

  GoogleGeocodingService.withClient(
    this._env, {
    required this._client,
  });

  final Env _env;
  final http.Client _client;

  Future<String?> reverseGeocode(Coordinates coordinates) async {
    final apiKey = _env.googleMapsApiKey;
    if (apiKey.isEmpty) {
      throw StateError('GOOGLE_MAPS_API_KEY is not configured');
    }

    // The classic REST endpoint rejects HTTP-referrer-restricted keys
    // outright ("API keys with referrer restrictions cannot be used with
    // this API") — exactly the key type a browser deployment needs for the
    // Maps JS SDK. Go through that already-loaded SDK's own Geocoder
    // instead, which runs in-browser under the same trusted referrer.
    if (kIsWeb) {
      return reverseGeocodeWithJsSdk(coordinates);
    }

    final response = await _client.get(
      Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': '${coordinates.lat},${coordinates.long}',
        'key': apiKey,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        googleMapsHttpFailureLabel(
          serviceName: 'Google Geocoding',
          statusCode: response.statusCode,
          body: response.body,
        ),
      );
    }

    final body = decodeGoogleMapsJsonObject(response.body);
    if (body['status'] != 'OK') return null;
    final results = readGoogleMapsJsonList(body['results']);
    if (results.isEmpty) return null;
    final first = results.first! as Map<String, Object?>;
    return first['formatted_address'] as String?;
  }
}
