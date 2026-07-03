import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/geo/data/service/google_geocoding_service.dart';
import 'package:tentura/features/geo/data/service/google_places_service.dart';

void main() {
  group('GooglePlacesService', () {
    test(
      'sends autocomplete request with API key, field mask, and token',
      () async {
        http.Request? seen;
        final service = GooglePlacesService.withClient(
          const Env(googleMapsApiKey: 'maps-key'),
          client: MockClient((request) async {
            seen = request;
            return http.Response(
              jsonEncode({
                'suggestions': [
                  {
                    'placePrediction': {
                      'placeId': 'place-1',
                      'text': {'text': 'Museumplein 6, Amsterdam'},
                    },
                  },
                ],
              }),
              200,
            );
          }),
        );

        final predictions = await service.autocomplete(
          input: 'Muse',
          sessionToken: 'token-1',
        );

        expect(seen!.method, 'POST');
        expect(
          seen!.url.toString(),
          'https://places.googleapis.com/v1/places:autocomplete',
        );
        expect(seen!.headers['X-Goog-Api-Key'], 'maps-key');
        expect(
          seen!.headers['X-Goog-FieldMask'],
          'suggestions.placePrediction.placeId,suggestions.placePrediction.text.text',
        );
        expect(jsonDecode(seen!.body), {
          'input': 'Muse',
          'sessionToken': 'token-1',
        });
        expect(predictions.single.placeId, 'place-1');
        expect(predictions.single.description, 'Museumplein 6, Amsterdam');
      },
    );

    test('resolves place details with the same session token', () async {
      http.Request? seen;
      final service = GooglePlacesService.withClient(
        const Env(googleMapsApiKey: 'maps-key'),
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'formattedAddress': 'Museumplein 6, Amsterdam',
              'location': {'latitude': 52.358, 'longitude': 4.881},
            }),
            200,
          );
        }),
      );

      final place = await service.details(
        placeId: 'place-1',
        sessionToken: 'token-1',
      );

      expect(
        seen!.url.toString(),
        'https://places.googleapis.com/v1/places/place-1?sessionToken=token-1',
      );
      expect(seen!.headers['X-Goog-Api-Key'], 'maps-key');
      expect(
        seen!.headers['X-Goog-FieldMask'],
        'location,formattedAddress,addressComponents',
      );
      expect(place.coordinates, const Coordinates(lat: 52.358, long: 4.881));
      expect(place.addressLabel, 'Museumplein 6, Amsterdam');
    });
  });

  group('GoogleGeocodingService', () {
    test('reverse geocodes coordinates to a stored address label', () async {
      http.Request? seen;
      final service = GoogleGeocodingService.withClient(
        const Env(googleMapsApiKey: 'maps-key'),
        client: MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode({
              'status': 'OK',
              'results': [
                {'formatted_address': 'Museumplein 6, Amsterdam'},
              ],
            }),
            200,
          );
        }),
      );

      final label = await service.reverseGeocode(
        const Coordinates(lat: 52.358, long: 4.881),
      );

      expect(
        seen!.url.toString(),
        'https://maps.googleapis.com/maps/api/geocode/json?latlng=52.358%2C4.881&key=maps-key',
      );
      expect(label, 'Museumplein 6, Amsterdam');
    });
  });
}
