import 'package:injectable/injectable.dart';

import '../entity/constellation_trust_chain_person.dart';
import '../port/constellation_trust_chain_port.dart';

@lazySingleton
final class ConstellationTrustChainCase {
  ConstellationTrustChainCase(this._port);

  final ConstellationTrustChainPort _port;

  /// The chain of trust from the viewer to [personId], viewer first.
  Future<List<ConstellationTrustChainPerson>> fetch(String personId) =>
      _port.fetchTrustChain(personId);
}
