import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/constellation_trust_chain_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class ConstellationTrustChainCase extends UseCaseBase {
  ConstellationTrustChainCase(
    this._port, {
    required super.env,
    required super.logger,
  });

  final ConstellationTrustChainPort _port;

  Future<List<ConstellationTrustChainPerson>> trustChain({
    required String viewerId,
    required String context,
    required String personId,
  }) {
    if (viewerId.trim().isEmpty || personId.trim().isEmpty) {
      return Future.value(const []);
    }
    return _port.trustChain(
      viewerId: viewerId,
      context: context,
      personId: personId,
    );
  }
}
