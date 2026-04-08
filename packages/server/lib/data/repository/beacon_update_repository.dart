import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/beacon_update_entity.dart';

import '../database/tentura_db.dart';

@Injectable(
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class BeaconUpdateRepository {
  const BeaconUpdateRepository(this._database);

  final TenturaDb _database;

  Future<void> create({
    required String beaconId,
    required String authorId,
    required String content,
  }) => _database.managers.beaconUpdates.create(
    (o) => o(
      beaconId: beaconId,
      authorId: authorId,
      content: content,
    ),
  );

  Future<List<BeaconUpdateEntity>> fetchByBeaconId(String beaconId) =>
      _database.managers.beaconUpdates
          .filter((e) => e.beaconId.id(beaconId))
          .orderBy((e) => e.createdAt.desc())
          .get()
          .then((rows) => rows.map(_toEntity).toList());

  static BeaconUpdateEntity _toEntity(BeaconUpdate row) =>
      BeaconUpdateEntity(
        id: row.id,
        beaconId: row.beaconId,
        authorId: row.authorId,
        content: row.content,
        createdAt: row.createdAt.dateTime,
      );
}
