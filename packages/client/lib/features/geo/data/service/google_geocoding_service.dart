import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/env.dart';

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

    final response = await _client.get(
      Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': '${coordinates.lat},${coordinates.long}',
        'key': apiKey,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Google Geocoding request failed: ${response.statusCode}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, Object?>;
    if (body['status'] != 'OK') return null;
    final results = body['results'] as List<Object?>? ?? const [];
    if (results.isEmpty) return null;
    final first = results.first! as Map<String, Object?>;
    return first['formatted_address'] as String?;
  }
}
