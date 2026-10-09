import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/port/constellation_anchor_repository_port.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

/// Answers a batched `apply` from a fake repository's single-target writes,
/// so a harness that models upsert/delete latency also serves the outbox.
Future<ConstellationAnchorApplyResult> applyViaWrites(
  ConstellationWriteFake repository,
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

/// Fixture-only single-target hooks used to model latency and failures inside
/// batch responses. These are not part of the production repository protocol.
abstract interface class ConstellationWriteFake
    implements ConstellationAnchorRepositoryPort {
  Future<ConstellationAnchorUpsertResult> upsert({
    required ConstellationAnchorTarget target,
    required ConstellationAnchorPosition position,
  });
  Future<ConstellationAnchorDeleteResult> delete({
    required ConstellationAnchorTarget target,
  });
}

class ConstellationAnchorUpsertResult {
  const ConstellationAnchorUpsertResult({
    required this.anchor,
    required this.revision,
  });
  final ConstellationAnchor anchor;
  final ConstellationAnchorRevision revision;
}

class ConstellationAnchorDeleteResult {
  const ConstellationAnchorDeleteResult({
    required this.target,
    required this.revision,
  });
  final ConstellationAnchorTarget target;
  final ConstellationAnchorRevision revision;
}
