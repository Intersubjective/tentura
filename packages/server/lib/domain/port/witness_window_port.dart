import 'package:tentura_server/domain/capability/capability_evidence_models.dart';

abstract interface class WitnessWindowPort {
  /// Domain supplies admission policy; the adapter only materializes raw facts.
  ///
  /// Returns the top-[topK] peers **and** the ego's full explicitly-trusted
  /// population (unbounded — needed for the floor percentile).
  Future<RawWindowFacts> rawWindowFacts({
    required String egoId,
    required String normalizedContext,
    required int topK,
  });

  /// Persists the domain's computed witness weights.
  Future<void> storeWindow({
    required String egoId,
    required String normalizedContext,
    required List<WitnessWeight> weights,
  });

  Future<List<WitnessWeight>> cachedWindow({
    required String egoId,
    required String normalizedContext,
  });

  Future<void> invalidateFor({required String userId});

  Future<void> bumpMrEpoch();

  /// Deletes witness-window cache rows past the read-time freshness TTL.
  Future<int> gcStaleWindows();
}
