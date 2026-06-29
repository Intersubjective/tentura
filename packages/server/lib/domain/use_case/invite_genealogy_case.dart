import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/invite_genealogy_graph_entity.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';

import '_use_case_base.dart';

@Injectable(order: 2)
final class InviteGenealogyCase extends UseCaseBase {
  InviteGenealogyCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  final InviteGenealogyRepositoryPort _repository;

  Future<InviteGenealogyGraphEntity> fetchLineage({
    required String viewerId,
  }) =>
      _repository.fetchLineage(userId: viewerId);
}
