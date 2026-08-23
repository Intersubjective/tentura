import '../entity/candidate_connection_context.dart';

abstract interface class ForwardCandidateContextRepositoryPort {
  Future<CandidateConnectionContext> load({
    required String candidateId,
    required String context,
  });
}
