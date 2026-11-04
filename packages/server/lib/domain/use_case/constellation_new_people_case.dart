import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/constellation_new_people_repository_port.dart';

import '_use_case_base.dart';

@Singleton(order: 2)
final class ConstellationNewPeopleCase extends UseCaseBase {
  ConstellationNewPeopleCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  final ConstellationNewPeopleRepositoryPort _repository;

  Future<void> acknowledge({
    required String viewerId,
    required List<String> peerIds,
  }) => _repository.acknowledge(viewerId: viewerId, peerIds: peerIds);
}
