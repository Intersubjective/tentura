import 'package:injectable/injectable.dart';

import '../entity/constellation_field.dart';
import '../port/constellation_member_webs_port.dart';

@lazySingleton
final class ConstellationMemberWebsCase {
  ConstellationMemberWebsCase(this._port);

  final ConstellationMemberWebsPort _port;

  Future<List<ConstellationMemberWeb>> fetch(String beaconId) =>
      _port.fetch(beaconId);
}
