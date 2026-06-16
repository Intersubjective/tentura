/// Semantic buckets for subjective user→user trust evidence.
enum TrustBin {
  veryBad(-5),
  bad(-1),
  noEffect(0),
  good(1),
  veryGood(5);

  const TrustBin(this.weight);

  final double weight;
}

/// Laplace prior mass per bin (α₀).
const double kTrustLaplacePrior = 1;

/// Vote/subscribe evidence magnitude.
const double kTrustVoteEvidenceCount = 3;

/// Beacon review evidence magnitude.
const double kTrustReviewEvidenceCount = 1;
