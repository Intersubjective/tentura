import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/constellation_mutual_trust_port.dart';

import '_use_case_base.dart';

/// Who a person on the viewer's field trusts both ways: explicit trust marks
/// only, never derived links, among the people the viewer may see. Read when
/// the viewer selects that person; the visible set comes from the
/// cross-request cache (m0235) and is computed (one MeritRank call) on a miss.
@Singleton(order: 2)
final class ConstellationMutualTrustCase extends UseCaseBase {
  ConstellationMutualTrustCase(
    this._port, {
    required super.env,
    required super.logger,
  });

  final ConstellationMutualTrustPort _port;

  /// Ids of the people [personId] trusts and who trust [personId] back, the
  /// viewer included when that is so; empty for a person the viewer may not
  /// see.
  Future<Set<String>> mutualTrustPartners({
    required String viewerId,
    required String context,
    required String personId,
  }) async {
    if (viewerId.trim().isEmpty || personId.trim().isEmpty) {
      return const {};
    }
    final edges = await _port.explicitTrustEdgesOf(
      viewerId: viewerId,
      context: context,
      personId: personId,
    );
    final trusted = <String>{};
    final trustedBy = <String>{};
    for (final edge in edges) {
      if (edge.tier != 1 || edge.src == edge.dst) continue;
      if (edge.src == personId) trusted.add(edge.dst);
      if (edge.dst == personId) trustedBy.add(edge.src);
    }
    return trusted.intersection(trustedBy);
  }
}
