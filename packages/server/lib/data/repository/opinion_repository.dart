import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/opinion_entity.dart';

import '../database/tentura_db.dart';
import '../mapper/opinion_mapper.dart';

@Injectable(
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class OpinionRepository {
  OpinionRepository(this._database);

  final TenturaDb _database;

  Future<OpinionEntity> getOpinionById(String id) async {
    final (opinion, opinionRefs) = await _database.managers.opinions
        .filter((e) => e.id.equals(id))
        .withReferences((p) => p(subject: true, object: true))
        .getSingle();

    return opinionModelToEntity(
      opinion,
      subject: await opinionRefs.subject.getSingle(),
      object: await opinionRefs.object.getSingle(),
    );
  }
}
