abstract interface class CapabilityTelemetryPort {
  /// Population-wide seed renewal gauge: triples with seed-channel ledger rows
  /// vs triples renewed by a forward reason before cell expiry.
  Future<({int seedTriples, int renewed})> countSeedRenewal();
}
