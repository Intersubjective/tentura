import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/forward_candidate_graph_snapshot.dart';
import 'package:tentura_server/domain/port/forward_candidate_context_repository_port.dart';

/// Safe default used by the test DI graph. Unit tests inject explicit
/// snapshots at the use-case boundary.
@LazySingleton(
  as: ForwardCandidateContextRepositoryPort,
  env: [Environment.test],
  order: 1,
)
final class ForwardCandidateContextRepositoryMock
    implements ForwardCandidateContextRepositoryPort {
  @override
  Future<ForwardCandidateGraphSnapshot> loadSnapshot({
    required String viewerId,
    required String candidateId,
    required String context,
  }) async => const ForwardCandidateGraphSnapshot.unavailable();
}
