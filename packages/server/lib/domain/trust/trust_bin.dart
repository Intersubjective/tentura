/// Semantic buckets for subjective user→user trust evidence.
enum TrustBin {
  veryBad('very_bad'),
  bad('bad'),
  noEffect('no_effect'),
  good('good'),
  veryGood('very_good');

  const TrustBin(this.key);

  /// Stable snake_case key passed to SQL trust_apply_source_evidence.
  final String key;
}

/// Vote/subscribe evidence magnitude.
const double kTrustVoteEvidenceCount = 3;

/// Beacon review evidence magnitude.
const double kTrustReviewEvidenceCount = 1;

/// Forward route no-effect evidence magnitude (env-overridable via
/// [Env.forwardNoEffectCount]).
const double kTrustForwardNoEffectCount = 1.0;
