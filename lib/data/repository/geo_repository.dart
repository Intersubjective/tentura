import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart'
    if (dart.library.js_interop) '../service/geocoding_web_service.dart';

import 'package:tentura/domain/entity/geo.dart';

export 'package:tentura/domain/entity/geo.dart';

class GeoRepository {
  GeoRepository({
    bool fetchOnCreate = true,
  }) {
    if (fetchOnCreate) getMyCoords();
  }

  final Map<Coordinates, Place?> cache = {};

  Coordinates? _myCoords;

  Coordinates? get myCoordinates => _myCoords;

  Future<Place?> getPlaceNameByCoords(
    Coordinates coords, {
    bool useCache = true,
  }) async {
    if (kIsWeb) return null;
    if (useCache && cache.containsKey(coords)) return cache[coords];
    try {
      final places = await placemarkFromCoordinates(coords.lat, coords.long);
      return cache[coords] = places.isEmpty
          ? null
          : (
              country: places.first.country,
              locality: places.first.locality,
            );
    } catch (_) {
      return null;
    }
  }

  Future<Coordinates?> getMyCoords({
    Duration timeLimit = const Duration(seconds: 30),
  }) async {
    if (_myCoords != null) return _myCoords;

    if (await _checkLocationPermission()) {
      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.lowest,
            timeLimit: timeLimit,
          ),
        );
        return _myCoords = (lat: position.latitude, long: position.longitude);
      } catch (e) {
        if (kDebugMode) print(e);
      }
    }
    return null;
  }

  Future<bool> _checkLocationPermission() async {
    if (await Geolocator.isLocationServiceEnabled()) {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) return true;

      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) return true;
    }
    return false;
  }
}
