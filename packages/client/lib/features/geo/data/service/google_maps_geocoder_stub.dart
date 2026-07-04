import 'package:tentura/domain/entity/coordinates.dart';

/// Non-web platforms never call this: `GoogleGeocodingService` only takes
/// the JS-SDK path when `kIsWeb`, and reach the REST API directly otherwise.
Future<String?> reverseGeocodeWithJsSdk(Coordinates coordinates) async => null;
