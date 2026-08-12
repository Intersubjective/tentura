import 'package:tentura_server/domain/capability/capability_evidence_models.dart';

abstract interface class BandCandidatePort {
  Future<List<BandCandidate>> candidatesFor({
    required String egoId,
    required String beaconId,
    required String normalizedContext,
  });

  /// Includes CANCELLED and historical edges, keyed on
  /// `beacon_forward_edge.created_at`. [candidatesFor] already excludes
  /// active forwards, so an active-only implementation would always return
  /// empty and silently disable the exploration exclusion.
  Future<Set<String>> recentlyForwardedTo({
    required String egoId,
    required int withinDays,
  });
}
