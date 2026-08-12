import 'package:freezed_annotation/freezed_annotation.dart';

part 'capability_evidence_models.freezed.dart';

enum EvidenceChannel { outcome, seed }

/// Declaration order is channel-first precedence (D2, architecture §5.4).
enum ProjectionTier {
  ownOutcome,
  networkOutcome,
  ownRouting,
  networkSeed,
}

enum ProjectionSurface { forwardBand, profile }

enum PromptStateValue { pending, answered, skipped }

@freezed
abstract class WitnessWeight with _$WitnessWeight {
  const factory WitnessWeight({
    required String witnessUserId,
    required double m,
    required bool admitted,
  }) = _WitnessWeight;
}

@freezed
abstract class RawPeerFact with _$RawPeerFact {
  const factory RawPeerFact({
    required String peerId,
    required double forwardMr,
    required bool explicitlyTrusted,
  }) = _RawPeerFact;
}

@freezed
abstract class RawWindowFacts with _$RawWindowFacts {
  const factory RawWindowFacts({
    required List<RawPeerFact> topPeers,
    required List<double> trustedScores,
  }) = _RawWindowFacts;
}

/// SQL-computed effective strengths (`cap_strength` applied). Raw accumulators
/// (`s_out`, `s_seed`, `anchor_at`) must not cross this boundary.
@freezed
abstract class WitnessCellRow with _$WitnessCellRow {
  const factory WitnessCellRow({
    required String observerUserId,
    required String subjectUserId,
    required String tagSlug,
    required double eOut,
    required double eSeed,
    required double m,
  }) = _WitnessCellRow;
}

@freezed
abstract class CellRef with _$CellRef {
  const factory CellRef({
    required String observerUserId,
    required String subjectUserId,
    required String tagSlug,
  }) = _CellRef;
}

@freezed
abstract class OwnEvidenceRow with _$OwnEvidenceRow {
  const factory OwnEvidenceRow({
    required String subjectUserId,
    required String tagSlug,
    required EvidenceChannel channel,
  }) = _OwnEvidenceRow;
}

@freezed
abstract class TombstoneRef with _$TombstoneRef {
  const factory TombstoneRef({
    required String subjectUserId,
    required String tagSlug,
  }) = _TombstoneRef;
}

/// Internal to projection/band use cases — never crosses the API boundary.
@freezed
abstract class ScoredProjection with _$ScoredProjection {
  const factory ScoredProjection({
    required String subjectUserId,
    required String tagSlug,
    required ProjectionTier tier,
    required EvidenceChannel channel,
    required double score,
  }) = _ScoredProjection;
}

/// API-facing projection; carries no score.
@freezed
abstract class TagProjection with _$TagProjection {
  const factory TagProjection({
    required String subjectUserId,
    required String tagSlug,
    required ProjectionTier tier,
  }) = _TagProjection;
}

@freezed
abstract class ForwardBandRow with _$ForwardBandRow {
  const factory ForwardBandRow({
    required String userId,
    required ProjectionTier? rowTier,
    required List<TagProjection> labels,
    required int rank,
    required bool isExploration,
  }) = _ForwardBandRow;
}

@freezed
abstract class OutcomeEmission with _$OutcomeEmission {
  const factory OutcomeEmission({
    required String observerUserId,
    required String subjectUserId,
    required String tagSlug,
  }) = _OutcomeEmission;
}

@freezed
abstract class PromptState with _$PromptState {
  const factory PromptState({
    required String inviterUserId,
    required String inviteeUserId,
    required PromptStateValue state,
  }) = _PromptState;
}

@freezed
abstract class BandCandidate with _$BandCandidate {
  const factory BandCandidate({
    required String userId,
    required double forwardMr,
    required bool canForwardTo,
    required bool alreadyForwarded,
    DateTime? lastForwardedAt,
  }) = _BandCandidate;
}
