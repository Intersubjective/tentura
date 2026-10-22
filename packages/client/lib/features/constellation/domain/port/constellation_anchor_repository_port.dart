import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../entity/constellation_anchor_projection.dart';

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

abstract interface class ConstellationAnchorRepositoryPort {
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  });

  /// Removes every user-placed position of the account; a retry with the
  /// same [clientOpId] returns the recorded outcome.
  Future<ConstellationAnchorResetResult> reset({required String clientOpId});
}
