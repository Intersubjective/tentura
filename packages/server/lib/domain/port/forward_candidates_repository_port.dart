import 'package:tentura_server/domain/entity/forward_candidate_peer_row.dart';

abstract class ForwardCandidatesRepositoryPort {
  /// Mutually visible users for [viewerId] in [context], with MR value scores
  /// from `person_visibility_peers`, followed by bond-only peers with zero
  /// MR/trust flags. Includes current mutual trust start times for both groups.
  /// Empty [viewerId] yields an empty list.
  Future<List<ForwardCandidatePeerRow>> fetchVisiblePeers({
    required String viewerId,
    required String context,
  });

  /// Timestamps of [viewerId]'s own forwards at or after [since], grouped by
  /// recipient id. Read-only; blank [viewerId] yields an empty map.
  Future<Map<String, List<DateTime>>> fetchRecentOwnForwardTimes({
    required String viewerId,
    required DateTime since,
  });
}
