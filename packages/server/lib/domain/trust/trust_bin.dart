/// Semantic buckets for subjective user→user trust evidence.
enum TrustBin {
  veryBad('very_bad'),
  bad('bad'),
  noEffect('no_effect'),
  good('good'),
  veryGood('very_good');

  const TrustBin(this.key);

  /// Stable snake_case key of the evidence ledger bins.
  final String key;
}

/// Vote/subscribe evidence magnitude.
const double kTrustVoteEvidenceCount = 3;

/// Beacon review evidence magnitude.
const double kTrustReviewEvidenceCount = 1;
