import 'package:injectable/injectable.dart';

import '../entity/candidate_connection_context.dart';
import '../port/forward_candidate_context_repository_port.dart';

@Order(2)
@singleton
final class LoadForwardCandidateContextCase {
  LoadForwardCandidateContextCase(this._repository);

  final ForwardCandidateContextRepositoryPort _repository;

  Future<CandidateConnectionContext> load({
    required String candidateId,
    required String context,
  }) => _repository.load(candidateId: candidateId, context: context);
}
