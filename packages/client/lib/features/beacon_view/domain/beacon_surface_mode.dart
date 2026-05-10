/// Top-level UI surface inside the beacon detail screen.
enum BeaconSurfaceMode {
  status,
  room,
}

extension BeaconSurfaceModeWire on BeaconSurfaceMode {
  /// Persisted in Drift `settings.valueText`.
  String get wire => switch (this) {
    BeaconSurfaceMode.status => 'status',
    BeaconSurfaceMode.room => 'room',
  };

  static BeaconSurfaceMode? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    switch (raw.trim().toLowerCase()) {
      case 'room':
        return BeaconSurfaceMode.room;
      case 'status':
        return BeaconSurfaceMode.status;
      default:
        return null;
    }
  }
}
