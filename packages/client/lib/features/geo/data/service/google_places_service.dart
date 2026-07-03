import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/env.dart';

final class GooglePlacePrediction {
  const GooglePlacePrediction({
    required this.placeId,
    required this.description,
  });

  final String placeId;
  final String description;
}

final class GoogleResolvedPlace {
  const GoogleResolvedPlace({
    required this.coordinates,
    required this.addressLabel,
  });

  final Coordinates coordinates;
  final String addressLabel;
}

@lazySingleton
class GooglePlacesService {
  GooglePlacesService(Env env) : this.withClient(env, client: http.Client());

  GooglePlacesService.withClient(
    this._env, {
    required this._client,
  });

  static const _autocompleteFieldMask =
      'suggestions.placePrediction.placeId,suggestions.placePrediction.text.text';
  static const _detailsFieldMask =
      'location,formattedAddress,addressComponents';

  final Env _env;
  final http.Client _client;

  Future<List<GooglePlacePrediction>> autocomplete({
    required String input,
    required String sessionToken,
  }) async {
    final response = await _client.post(
      Uri.https('places.googleapis.com', '/v1/places:autocomplete'),
      headers: _headers(fieldMask: _autocompleteFieldMask),
      body: jsonEncode({
        'input': input,
        'sessionToken': sessionToken,
      }),
    );
    _throwIfFailed(response);

    final body = jsonDecode(response.body) as Map<String, Object?>;
    final suggestions = body['suggestions'] as List<Object?>? ?? const [];
    return [
      for (final suggestion in suggestions)
        if (suggestion case {'placePrediction': final Map<String, Object?> p})
          GooglePlacePrediction(
            placeId: p['placeId'] as String? ?? '',
            description:
                ((p['text'] as Map<String, Object?>?)?['text'] as String?) ??
                '',
          ),
    ].where((p) => p.placeId.isNotEmpty && p.description.isNotEmpty).toList();
  }

  Future<GoogleResolvedPlace> details({
    required String placeId,
    required String sessionToken,
  }) async {
    final response = await _client.get(
      Uri.https('places.googleapis.com', '/v1/places/$placeId', {
        'sessionToken': sessionToken,
      }),
      headers: _headers(fieldMask: _detailsFieldMask),
    );
    _throwIfFailed(response);

    final body = jsonDecode(response.body) as Map<String, Object?>;
    final location = body['location'] as Map<String, Object?>? ?? const {};
    return GoogleResolvedPlace(
      coordinates: Coordinates(
        lat: (location['latitude']! as num).toDouble(),
        long: (location['longitude']! as num).toDouble(),
      ),
      addressLabel: body['formattedAddress'] as String? ?? '',
    );
  }

  Map<String, String> _headers({required String fieldMask}) {
    final apiKey = _env.googleMapsApiKey;
    if (apiKey.isEmpty) {
      throw StateError('GOOGLE_MAPS_API_KEY is not configured');
    }
    return {
      'Content-Type': 'application/json',
      'X-Goog-Api-Key': apiKey,
      'X-Goog-FieldMask': fieldMask,
    };
  }

  void _throwIfFailed(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('Google Places request failed: ${response.statusCode}');
    }
  }
}
