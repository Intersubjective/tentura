import 'package:injectable/injectable.dart';

import '../port/constellation_mutual_trust_port.dart';

@lazySingleton
final class ConstellationMutualTrustCase {
  ConstellationMutualTrustCase(this._port);

  final ConstellationMutualTrustPort _port;

  /// Who [personId] trusts both ways, among the people the viewer may see.
  Future<Set<String>> fetch(String personId) =>
      _port.fetchMutualTrust(personId);
}
