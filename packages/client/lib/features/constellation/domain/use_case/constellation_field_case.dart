import 'package:injectable/injectable.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../constellation_cap_policy.dart';
import '../constellation_consts.dart';
import '../constellation_path_resolution.dart';
import '../entity/constellation_field.dart';
import '../port/constellation_repository_port.dart';

typedef ConstellationFieldResolved = ({
  ConstellationField field,
  ConstellationPathResolution paths,
  Set<String> keptPeerIds,
  Set<String> droppedHolderIds,
  bool capped,
});

@Order(2)
@singleton
final class ConstellationFieldCase extends UseCaseBase {
  ConstellationFieldCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  final ConstellationRepositoryPort _repository;

  Future<ConstellationFieldResolved> load({required String viewerId}) async {
    final field = await _repository.fetch();
    final visiblePeerIds = field.peers.map((peer) => peer.id);
    final holderIds = {
      viewerId,
      ...field.requests.map((request) => request.authorId),
    };
    final edges = field.edges.map(
      (edge) => (
        src: edge.src,
        dst: edge.dst,
        tier: edge.tier,
      ),
    );

    final resolved = resolveAndCapConstellation(
      egoId: viewerId,
      visiblePeerIds: visiblePeerIds,
      holderIds: holderIds,
      edges: edges,
      cap: kConstellationRenderPeerCap,
    );

    return (
      field: field,
      paths: resolved.paths,
      keptPeerIds: resolved.keptPeerIds,
      droppedHolderIds: resolved.droppedHolderIds,
      capped: resolved.capped,
    );
  }
}
