import 'coordinates.dart';

enum BeaconMapsPlatform {
  android,
  ios,
  web,
}

Uri beaconLocationMapsUri({
  required Coordinates coordinates,
  required String? label,
  required BeaconMapsPlatform platform,
}) {
  final lat = coordinates.lat.toString();
  final long = coordinates.long.toString();
  final coordinatePair = '$lat,$long';
  final cleanLabel = label?.trim();

  return switch (platform) {
    BeaconMapsPlatform.android => Uri.parse(
      cleanLabel == null || cleanLabel.isEmpty
          ? 'geo:$coordinatePair?q=$coordinatePair'
          : 'geo:$coordinatePair?q=$coordinatePair(${Uri.encodeComponent(cleanLabel)})',
    ),
    BeaconMapsPlatform.ios => Uri.https('maps.apple.com', '/', {
      'll': coordinatePair,
      'q': cleanLabel == null || cleanLabel.isEmpty
          ? coordinatePair
          : cleanLabel,
    }),
    BeaconMapsPlatform.web => Uri.https('www.google.com', '/maps/search/', {
      'api': '1',
      'query': coordinatePair,
    }),
  };
}
