import 'package:tentura_server/domain/entity/opinion_entity.dart';

abstract class OpinionRepositoryPort {
  Future<OpinionEntity> getOpinionById(String id);
}
