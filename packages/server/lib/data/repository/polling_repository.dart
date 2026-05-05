import 'package:drift/drift.dart';
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

  Future<Polling?> findById(String pollingId) =>
      _database.managers.pollings
          .filter((p) => p.id.equals(pollingId))
          .getSingleOrNull();

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

  Future<String> createWithVariants({
    required String authorId,
    required String question,
    required List<String> variants,
    String pollType = 'single',
    bool isAnonymous = true,
    bool allowRevote = true,
  }) =>
      _database.transaction(() async {
        final polling = await _database.managers.pollings.createReturning(
          (o) => o(
            id: Value(PollingEntity.newId),
            authorId: authorId,
            question: question,
            pollType: Value(pollType),
            isAnonymous: Value(isAnonymous),
            allowRevote: Value(allowRevote),
          ),
        );
        await _database.managers.pollingVariants.bulkCreate(
          (o) => variants.map((d) => o(pollingId: polling.id, description: d)),
        );
        return polling.id;
      });
}
