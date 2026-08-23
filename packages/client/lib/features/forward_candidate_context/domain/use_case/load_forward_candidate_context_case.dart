import 'package:injectable/injectable.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../entity/candidate_connection_context.dart';
import '../port/forward_candidate_context_repository_port.dart';

@singleton
final class LoadForwardCandidateContextCase extends UseCaseBase {
  LoadForwardCandidateContextCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  final ForwardCandidateContextRepositoryPort _repository;

  Future<CandidateConnectionContext> load({
    required String candidateId,
    required String context,
  }) => _repository.load(candidateId: candidateId, context: context);
}
