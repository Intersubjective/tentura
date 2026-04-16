import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/opinion_entity.dart';
import 'package:tentura_server/domain/port/opinion_repository_port.dart';

import '_use_case_base.dart';

@Injectable(order: 2)
final class OpinionCase extends UseCaseBase {
  OpinionCase(
    this._opinionRepository, {
    required super.env,
    required super.logger,
  });

  final OpinionRepositoryPort _opinionRepository;

  Future<OpinionEntity> getOpinionById(String id) =>
      _opinionRepository.getOpinionById(id);
}
