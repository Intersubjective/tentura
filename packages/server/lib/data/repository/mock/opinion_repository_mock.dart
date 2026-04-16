import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/opinion_entity.dart';

import 'package:tentura_server/domain/port/opinion_repository_port.dart';

import 'data/opinions.dart';

@Injectable(
  as: OpinionRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class OpinionRepositoryMock implements OpinionRepositoryPort {
  final storageById = <String, OpinionEntity>{...kOpinionsById};

  @override
  Future<OpinionEntity> getOpinionById(String id) async {
    final v = storageById[id];
    if (v == null) {
      throw StateError('Unknown opinion id: $id');
    }
    return v;
  }
}
