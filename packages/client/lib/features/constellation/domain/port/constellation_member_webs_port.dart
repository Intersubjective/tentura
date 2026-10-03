import '../entity/constellation_field.dart';

abstract interface class ConstellationMemberWebsPort {
  /// Member webs of one Request, fetched lazily when it is selected.
  Future<List<ConstellationMemberWeb>> fetch(String beaconId);
}
