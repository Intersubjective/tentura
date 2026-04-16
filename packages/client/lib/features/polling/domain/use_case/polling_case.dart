import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/polling.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../../data/repository/polling_repository.dart';
import '../entity/polling_result.dart';

@singleton
final class PollingCase extends UseCaseBase {
  PollingCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  final PollingRepository _repository;

  Future<void> vote({
    required String pollingId,
    required String variantId,
  }) =>
      _repository.vote(
        pollingId: pollingId,
        variantId: variantId,
      );

  Future<({Polling polling, List<PollingResult> results})> fetchResults({
    required String pollingId,
  }) =>
      _repository.fetchResults(pollingId: pollingId);
}
