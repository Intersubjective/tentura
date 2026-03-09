import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/polling_entity.dart';

import '../database/tentura_db.dart';

@Injectable(
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class PollingRepository {
  const PollingRepository(this._database);

  final TenturaDb _database;

  Future<String> create({
    required String authorId,
    required String question,
  }) async {
    final polling = await _database.managers.pollings.createReturning(
      (o) => o(
        id: Value(PollingEntity.newId),
        authorId: authorId,
        question: question,
      ),
    );
    return polling.id;
  }
}
