import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/opinion_entity.dart';

import '../opinion_repository.dart';
import 'data/opinions.dart';

@Injectable(
  as: OpinionRepository,
  env: [Environment.test],
  order: 1,
)
class OpinionRepositoryMock implements OpinionRepository {
  final storageById = <String, OpinionEntity>{...kOpinionsById};

  @override
  Future<OpinionEntity> getOpinionById(String id) => Future.value(
    storageById[id],
  );
}
