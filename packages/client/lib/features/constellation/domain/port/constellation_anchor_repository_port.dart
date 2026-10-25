import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../entity/constellation_anchor_projection.dart';
import '../entity/constellation_layout_snapshot.dart';

part 'constellation_anchor_repository_port.freezed.dart';

enum ConstellationAnchorOpKind { upsert, delete }

enum ConstellationAnchorOpStatus { ok, rejected }

/// One ordered operation of a batched anchor apply; [position] is required for
/// upserts and [ifRevision] guards against a stale per-target revision.
/// [baseRevision] is the account anchor revision the client held when the
/// user made the write: the server rejects it (reason `reset`) when a reset
/// happened after that (#251).
@freezed
abstract class ConstellationAnchorApplyOp with _$ConstellationAnchorApplyOp {
  const factory ConstellationAnchorApplyOp({
    required String clientOpId,
    required ConstellationAnchorOpKind kind,
    required ConstellationAnchorTarget target,
    ConstellationAnchorPosition? position,
    ConstellationAnchorRevision? ifRevision,
    ConstellationAnchorRevision? baseRevision,
  }) = _ConstellationAnchorApplyOp;
}

@freezed
abstract class ConstellationAnchorOpResult with _$ConstellationAnchorOpResult {
  const factory ConstellationAnchorOpResult({
    required String clientOpId,
    required ConstellationAnchorOpStatus status,
    String? reason,
    ConstellationAnchorRevision? resultingTargetRevision,
    // The op's target, as sent.
    ConstellationAnchorTarget? target,
    // Stored row of an executed upsert.
    ConstellationAnchor? anchor,
    // The recorded result of an earlier execution; never merged.
    @Default(false) bool replayed,
  }) = _ConstellationAnchorOpResult;
}

@freezed
abstract class ConstellationAnchorApplyResult
    with _$ConstellationAnchorApplyResult {
  const factory ConstellationAnchorApplyResult({
    required ConstellationAnchorRevision beforeRevision,
    required ConstellationAnchorRevision afterRevision,
    required List<ConstellationAnchorOpResult> results,
  }) = _ConstellationAnchorApplyResult;
}

/// Outcome of «Сбросить позиции» (#251).
@freezed
abstract class ConstellationAnchorResetResult
    with _$ConstellationAnchorResetResult {
  const factory ConstellationAnchorResetResult({
    required ConstellationAnchorRevision beforeRevision,

    /// The account anchor revision after the reset; also the reset watermark.
    required ConstellationAnchorRevision afterRevision,
    required int clearedCount,

    /// The same operation id was already applied; nothing was written again.
    @Default(false) bool replayed,
  }) = _ConstellationAnchorResetResult;
}

/// The newest saved layout: what a reset that saved history has just written,
/// whose id the reset does not return.
const kLatestLayoutSnapshotId = '';

abstract interface class ConstellationAnchorRepositoryPort {
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  });

  /// Removes every user-placed position of the account; a retry with the
  /// same [clientOpId] returns the recorded outcome. With [saveHistory] the
  /// layout it clears is saved in the same call, so the reset can be undone.
  Future<ConstellationAnchorResetResult> reset({
    required String clientOpId,
    bool saveHistory = false,
  });

  /// Saves the viewer's current layout as a history snapshot of [reason]
  /// (`manual`, `restore`, `reset` or `rebuild`) and returns its id; a retry
  /// with the same [clientOpId] saves nothing again.
  Future<String> saveLayoutSnapshot({
    required String reason,
    required String clientOpId,
  });

  /// Puts the saved layout [snapshotId] back in one step; a retry with the
  /// same [clientOpId] writes nothing again. The layout it replaces is saved
  /// first and its id returned, so the restore can itself be undone.
  /// [kLatestLayoutSnapshotId] stands for the newest saved layout.
  Future<String> restoreLayoutSnapshot({
    required String snapshotId,
    required String clientOpId,
  });
}

/// Read-only snapshot browsing and favourite writes, separate from placements.
abstract interface class ConstellationLayoutSnapshotRepositoryPort {
  Future<List<ConstellationLayoutSnapshot>> listLayoutSnapshots();
  Future<String> saveFavourite({required String clientOpId});
  Future<void> restoreFavourite({
    required String snapshotId,
    required String clientOpId,
  });
}
