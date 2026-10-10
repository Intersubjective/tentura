import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura_root/domain/constellation/constellation_anchor.dart';

import '../entity/constellation_anchor_projection.dart';

part 'constellation_anchor_repository_port.freezed.dart';

enum ConstellationAnchorOpKind { upsert, delete }

enum ConstellationAnchorOpStatus { ok, rejected }

/// One ordered operation of a batched anchor apply; [position] is required for
/// upserts and [ifRevision] guards against a stale per-target revision.
@freezed
abstract class ConstellationAnchorApplyOp with _$ConstellationAnchorApplyOp {
  const factory ConstellationAnchorApplyOp({
    required String clientOpId,
    required ConstellationAnchorOpKind kind,
    required ConstellationAnchorTarget target,
    ConstellationAnchorPosition? position,
    ConstellationAnchorRevision? ifRevision,
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

// ignore: one_member_abstracts -- injectable boundary with a test replacement
abstract interface class ConstellationAnchorRepositoryPort {
  Future<ConstellationAnchorApplyResult> apply({
    required List<ConstellationAnchorApplyOp> ops,
    required ConstellationFieldMembershipFilters params,
  });
}
