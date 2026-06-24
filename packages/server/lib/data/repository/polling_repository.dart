import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/polling_entity.dart';
import 'package:tentura_server/domain/entity/beacon_room_record.dart';
import 'package:tentura_server/domain/port/polling_repository_port.dart';

import '../database/tentura_db.dart';
import 'mappers/coordination_row_mappers.dart';

@Injectable(
  as: PollingRepositoryPort,
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class PollingRepository implements PollingRepositoryPort {
  const PollingRepository(this._database);

  final TenturaDb _database;

  @override
  Future<PollingVotePolicy?> findById(String pollingId) async {
    final row = await _database.managers.pollings
        .filter((p) => p.id.equals(pollingId))
        .getSingleOrNull();
    return row?.toVotePolicy();
  }

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
