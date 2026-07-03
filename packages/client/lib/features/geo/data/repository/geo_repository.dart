import 'dart:async';

import 'package:logging/logging.dart';
import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:geolocator/geolocator.dart';

import 'package:tentura/app/sentry/report_user_facing_error.dart';
import 'package:tentura/domain/entity/coordinates.dart';

@Singleton(env: [Environment.dev, Environment.prod])
class GeoRepository {
  GeoRepository(this._logger);

  final Logger _logger;

  Coordinates? _myCoords;

  Coordinates? get myCoordinates => _myCoords;

  @PostConstruct()
  void init() {
    // Web: skip eager geolocation — geolocator_web checkPermission() calls
    // navigator.permissions.query which throws Illegal invocation in Chrome.
    if (kIsWeb) return;
    unawaited(getMyCoords());
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
        return _myCoords = Coordinates(
          lat: position.latitude,
          long: position.longitude,
        );
      } catch (e) {
        _logger.warning('Failed to read current location: $e');
        reportUserFacingError(e);
      }
    }
    return null;
  }

  Future<bool> _checkLocationPermission() async {
    if (await Geolocator.isLocationServiceEnabled()) {
      if (kIsWeb) {
        // geolocator_web routes checkPermission() through permissions.query,
        // which throws TypeError: Illegal invocation in Chrome (js_interop).
        // Browser geolocation permission is resolved by getCurrentPosition().
        return true;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        return true;
      }

      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        return true;
      }
    }
    return false;
  }
}
