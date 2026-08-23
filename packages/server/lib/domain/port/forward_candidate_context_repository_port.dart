import 'package:tentura_server/domain/entity/forward_candidate_graph_snapshot.dart';

abstract interface class ForwardCandidateContextRepositoryPort {
  /// Reads candidate eligibility, filtered graph edges, and display
  /// projections from one database statement and one database snapshot.
  Future<ForwardCandidateGraphSnapshot> loadSnapshot({
    required String viewerId,
    required String candidateId,
    required String context,
  });
}
