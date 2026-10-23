import 'package:latlong2/latlong.dart';

class Coordinates extends LatLng {
  const Coordinates({required double lat, required double long})
    : super(lat, long);

  factory Coordinates.fromJson(Map<String, dynamic> json) =>
      Coordinates(lat: json['lat']! as double, long: json['long']! as double);

  double get lat => latitude;

  double get long => longitude;

  bool get isEmpty => latitude == 0 && longitude == 0;

  /// Any point other than the unset 0,0 value, including points on the
  /// equator or the prime meridian (one coordinate exactly 0).
  bool get isNotEmpty => !isEmpty;

  @override
  String toString() => '($latitude, $longitude)';

  @override
  Map<String, Object> toJson() => {'lat': latitude, 'long': longitude};

  static const zero = Coordinates(lat: 0, long: 0);
}
