abstract interface class CapabilityTelemetryPort {
  /// Population-wide seed renewal gauge: triples with seed-channel ledger rows
  /// vs triples renewed by a forward reason before cell expiry.
  Future<({int seedTriples, int renewed})> countSeedRenewal();

  /// Percentile summary of `forward_mr` for invite-genealogy depth-2 users
  /// (invited by someone the sampled ego invited), read via
  /// `person_visibility_peers` at blank context.
  Future<({int n, double? p33, double? p50, double? p75})>
  twoHopSponsoredForwardMrPercentiles();

  /// Sampled (ego, subject, tag) triples classified by θ-clearing with
  /// eligible witnesses only vs clearing only when ineligible witnesses count.
  Future<({int eligibleClearing, int ineligibleOnly})>
  countEligibleWitnessCoverage();
}
