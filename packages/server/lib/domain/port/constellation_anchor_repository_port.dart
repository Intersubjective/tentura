import 'package:tentura_root/domain/constellation/constellation_anchor.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';

enum AnchorOpKind {
  upsert('UPSERT'),
  delete('DELETE');

  const AnchorOpKind(this.wireValue);
  final String wireValue;
}

enum AnchorOpStatus {
  ok('OK'),
  rejected('REJECTED');

  const AnchorOpStatus(this.wireValue);
  final String wireValue;
}

class AnchorApplyOp {
  const AnchorApplyOp({
    required this.clientOpId,
    required this.kind,
    required this.target,
    this.position,
    this.ifRevision,
  });

  final String clientOpId;
  final AnchorOpKind kind;
  final ConstellationAnchorTarget target;
  final ConstellationAnchorPosition? position;
  final ConstellationAnchorRevision? ifRevision;
}

class AnchorApplyParams {
  const AnchorApplyParams({required this.context, required this.filters});

  final String context;
  final ConstellationFieldMembershipFilters filters;
}

class AnchorApplyOpResult {
  const AnchorApplyOpResult({
    required this.clientOpId,
    required this.status,
    this.reason,
    this.resultingTargetRevision,
    this.position,
  });

  final String clientOpId;
  final AnchorOpStatus status;
  final String? reason;
  final ConstellationAnchorRevision? resultingTargetRevision;
  final ConstellationAnchorPosition? position;
}

class AnchorApplyBatchResult {
  const AnchorApplyBatchResult({
    required this.beforeRevision,
    required this.afterRevision,
    required this.results,
    required this.projection,
  });

  final ConstellationAnchorRevision beforeRevision;
  final ConstellationAnchorRevision afterRevision;
  final List<AnchorApplyOpResult> results;
  final ConstellationAnchorProjection projection;
}

/// Account watermark after an anchor mutation (C3).
class ConstellationAnchorWatermark {
  const ConstellationAnchorWatermark(this.revision);

  final ConstellationAnchorRevision revision;
}

abstract interface class ConstellationAnchorRepositoryPort {
  Future<AnchorApplyBatchResult> applyBatch({
    required String viewerId,
    required List<AnchorApplyOp> ops,
    required AnchorApplyParams params,
  });

  /// Read-only cursor revision; returns revision zero when no cursor row exists.
  Future<ConstellationAnchorRevision> readWatermark(String viewerId);
}
