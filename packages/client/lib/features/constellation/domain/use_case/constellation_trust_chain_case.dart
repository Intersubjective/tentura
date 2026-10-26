import 'package:injectable/injectable.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../entity/constellation_trust_chain_person.dart';
import '../port/constellation_trust_chain_port.dart';

@lazySingleton
final class ConstellationTrustChainCase extends UseCaseBase {
  ConstellationTrustChainCase(
    this._port, {
    required super.env,
    required super.logger,
  });

  final ConstellationTrustChainPort _port;

  /// The chain of trust from the viewer to [personId], viewer first.
  Future<List<ConstellationTrustChainPerson>> fetch(String personId) =>
      _port.fetchTrustChain(personId);
}
