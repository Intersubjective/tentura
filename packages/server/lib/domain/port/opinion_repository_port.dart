import 'package:tentura_server/domain/entity/opinion_entity.dart';

// ignore: one_member_abstracts -- injectable port with a single repository entry point
abstract class OpinionRepositoryPort {
  Future<OpinionEntity> getOpinionById(String id);
}
