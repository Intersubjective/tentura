import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

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

class AnchorApplyOpResult {
  const AnchorApplyOpResult({
    required this.clientOpId,
    required this.status,
    this.reason,
    this.resultingTargetRevision,
    this.position,
    this.anchor,
    this.replayed = false,
  });

  final String clientOpId;
  final AnchorOpStatus status;
  final String? reason;
  final ConstellationAnchorRevision? resultingTargetRevision;
  final ConstellationAnchorPosition? position;
  final ConstellationAnchor? anchor;
  final bool replayed;
}

class AnchorApplyBatchResult {
  const AnchorApplyBatchResult({
    required this.beforeRevision,
    required this.afterRevision,
    required this.results,
  });

  final ConstellationAnchorRevision beforeRevision;
  final ConstellationAnchorRevision afterRevision;
  final List<AnchorApplyOpResult> results;
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
  });

  /// Read-only cursor revision; returns revision zero when no cursor row exists.
  Future<ConstellationAnchorRevision> readWatermark(String viewerId);
}
