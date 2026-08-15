import 'package:tentura_server/domain/entity/forward_candidate_peer_row.dart';

abstract class ForwardCandidatesRepositoryPort {
  /// Mutually visible users for [viewerId] in [context], with MR value scores
  /// from `person_visibility_peers`. Empty [viewerId] yields an empty list.
  Future<List<ForwardCandidatePeerRow>> fetchVisiblePeers({
    required String viewerId,
    required String context,
  });
}
