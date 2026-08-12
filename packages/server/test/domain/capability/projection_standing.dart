import 'package:tentura_server/domain/capability/capability_evidence_models.dart';

/// Qualitative ordering key for [ScoredProjection] rows.
///
/// Matches [ForwardBandCase]'s evidence sort: lower [ProjectionTier] index is
/// stronger, then higher [score] wins within a tier. Absent projections sort
/// below any present row so `greaterThan` means strictly stronger standing.
final class ProjectionStanding implements Comparable<ProjectionStanding> {
  const ProjectionStanding._({
    required this.tier,
    required this.score,
  });

  factory ProjectionStanding.fromProjection(ScoredProjection? projection) {
    if (projection == null) {
      return const ProjectionStanding._(tier: null, score: 0);
    }
    return ProjectionStanding._(
      tier: projection.tier,
      score: projection.score,
    );
  }

  final ProjectionTier? tier;
  final double score;

  bool get isPresent => tier != null;

  int _tierRank(ProjectionTier tier) => ProjectionTier.values.indexOf(tier);

  @override
  int compareTo(ProjectionStanding other) {
    if (tier == null && other.tier == null) {
      return 0;
    }
    if (tier == null) {
      return -1;
    }
    if (other.tier == null) {
      return 1;
    }

    final tierCmp = _tierRank(other.tier!) - _tierRank(tier!);
    if (tierCmp != 0) {
      return tierCmp;
    }
    return score.compareTo(other.score);
  }

  bool operator <(ProjectionStanding other) => compareTo(other) < 0;

  bool operator <=(ProjectionStanding other) => compareTo(other) <= 0;

  bool operator >(ProjectionStanding other) => compareTo(other) > 0;

  bool operator >=(ProjectionStanding other) => compareTo(other) >= 0;
}
