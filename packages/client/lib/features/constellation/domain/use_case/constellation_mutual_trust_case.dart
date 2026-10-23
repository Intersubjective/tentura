import 'package:injectable/injectable.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../port/constellation_mutual_trust_port.dart';

@lazySingleton
final class ConstellationMutualTrustCase extends UseCaseBase {
  ConstellationMutualTrustCase(
    this._port, {
    required super.env,
    required super.logger,
  });

  final ConstellationMutualTrustPort _port;

  /// Who [personId] trusts both ways, among the people the viewer may see.
  Future<Set<String>> fetch(String personId) =>
      _port.fetchMutualTrust(personId);
}
