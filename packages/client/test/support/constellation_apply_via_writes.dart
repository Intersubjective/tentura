import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

/// Answers a batched `apply` from a fake repository's single-target writes,
/// so a harness that models upsert/delete latency also serves the outbox.
Future<ConstellationAnchorApplyResult> applyViaWrites(
  ConstellationAnchorRepositoryPort repository,
  List<ConstellationAnchorApplyOp> ops,
) async {
  final anchors = <ConstellationAnchor>[];
  final results = <ConstellationAnchorOpResult>[];
  var revision = ConstellationAnchorRevision.zero;
  for (final op in ops) {
    if (op.kind == ConstellationAnchorOpKind.delete) {
      revision = (await repository.delete(target: op.target)).revision;
    } else {
      final result = await repository.upsert(
        target: op.target,
        position: op.position!,
      );
      revision = result.revision;
      anchors.add(result.anchor);
    }
    results.add(
      ConstellationAnchorOpResult(
        clientOpId: op.clientOpId,
        status: ConstellationAnchorOpStatus.ok,
        resultingTargetRevision: revision,
      ),
    );
  }
  return ConstellationAnchorApplyResult(
    beforeRevision: ConstellationAnchorRevision.zero,
    afterRevision: revision,
    results: results,
    anchorProjection: ConstellationAnchorProjection(
      revision: revision,
      anchors: anchors,
      pinnedPeers: const [],
      pinnedRequests: const [],
      supportPeers: const [],
      supportEdges: const [],
      serverFilteredBeaconIds: const [],
      serverFilteredBeaconCount: 0,
    ),
  );
}
