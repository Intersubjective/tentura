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
    this.baseRevision,
  });

  final String clientOpId;
  final AnchorOpKind kind;
  final ConstellationAnchorTarget target;
  final ConstellationAnchorPosition? position;
  final ConstellationAnchorRevision? ifRevision;

  /// The account anchor revision the client held when the user made this
  /// write. Below the viewer's reset watermark the write predates a reset
  /// (#251) and is rejected with reason `reset`. Null skips the check.
  final ConstellationAnchorRevision? baseRevision;
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

/// Outcome of resetting every anchor of a viewer (#251).
class AnchorResetResult {
  const AnchorResetResult({
    required this.beforeRevision,
    required this.afterRevision,
    required this.clearedCount,
    this.replayed = false,
  });

  final ConstellationAnchorRevision beforeRevision;

  /// The cursor revision after the reset; also the reset watermark.
  final ConstellationAnchorRevision afterRevision;

  /// Anchors removed, tombstones included.
  final int clearedCount;

  /// True when the reset's operation id was already applied: nothing was
  /// written again.
  final bool replayed;
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

  /// Removes every anchor of [viewerId] (all target kinds, tombstones too) in
  /// one transaction under the viewer's locks, advances the cursor (one
  /// realtime anchor hint) and stamps the reset watermark. Idempotent per
  /// [clientOpId]: a retry returns the recorded outcome. With [saveHistory]
  /// the cleared layout is first saved as a `reset` history snapshot in the
  /// same transaction, so a failed save leaves every anchor in place.
  Future<AnchorResetResult> resetAll({
    required String viewerId,
    required String clientOpId,
    bool saveHistory = false,
  });
}
