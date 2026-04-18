import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/beacon_update_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_update_repository_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: BeaconUpdateRepositoryPort,
  env: [
    Environment.dev,
    Environment.prod,
  ],
  order: 1,
)
class BeaconUpdateRepository implements BeaconUpdateRepositoryPort {
  const BeaconUpdateRepository(this._database);

  final TenturaDb _database;

  @override
  Future<BeaconUpdateEntity> createUpdate({
    required String beaconId,
    required String authorId,
    required String content,
  }) => _database.withMutatingUser(authorId, () => _database.transaction(() async {
    await _database.customSelect(
      'SELECT id FROM public.beacon WHERE id = ? FOR UPDATE',
      variables: [Variable<String>(beaconId)],
    ).getSingle();

    final nextRow = await _database.customSelect(
      '''
SELECT coalesce(max(number), 0) + 1 AS n
FROM public.beacon_update
WHERE beacon_id = ?
''',
      variables: [Variable<String>(beaconId)],
    ).getSingle();
    final n = nextRow.read<int>('n');

    final row = await _database.managers.beaconUpdates.createReturning(
      (o) => o(
        beaconId: beaconId,
        authorId: authorId,
        content: content,
        number: Value(n),
      ),
    );
    return _toEntity(row);
  }));

  @override
  Future<BeaconUpdateEntity> editUpdate({
    required String id,
    required String authorId,
    required String content,
  }) => _database.withMutatingUser(authorId, () async {
    final changed = await _database.managers.beaconUpdates
        .filter((e) => e.id.equals(id) & e.authorId.id(authorId))
        .update((o) => o(content: Value(content)));
    if (changed == 0) {
      throw IdNotFoundException(id: id, description: 'Beacon update not found');
    }
    final row = await _database.managers.beaconUpdates
        .filter((e) => e.id.equals(id))
        .getSingle();
    return _toEntity(row);
  });

  @override
  Future<BeaconUpdateEntity?> getById(String id) => _database.managers.beaconUpdates
      .filter((e) => e.id.equals(id))
      .getSingleOrNull()
      .then((r) => r == null ? null : _toEntity(r));

  @override
  Future<List<BeaconUpdateEntity>> fetchByBeaconId(String beaconId) =>
      _database.managers.beaconUpdates
          .filter((e) => e.beaconId.id(beaconId))
          .orderBy((e) => e.createdAt.desc())
          .get()
          .then((rows) => rows.map(_toEntity).toList());

  static BeaconUpdateEntity _toEntity(BeaconUpdate row) => BeaconUpdateEntity(
    id: row.id,
    beaconId: row.beaconId,
    authorId: row.authorId,
    content: row.content,
    number: row.number,
    createdAt: row.createdAt.dateTime,
  );
}
