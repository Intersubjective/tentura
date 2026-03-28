import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/domain/entity/commitment_entity.dart';

import '../database/tentura_db.dart';

@Injectable(
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class CommitmentRepository {
  const CommitmentRepository(this._database);

  final TenturaDb _database;

  Future<void> upsert({
    required String beaconId,
    required String userId,
    String message = '',
    int status = 0,
  }) => _database.managers.beaconCommitments.create(
    (o) => o(
      beaconId: beaconId,
      userId: userId,
      message: Value(message),
      status: Value(status),
    ),
    mode: InsertMode.insertOrReplace,
  );

  Future<void> withdraw({
    required String beaconId,
    required String userId,
  }) => _database.managers.beaconCommitments
      .filter(
        (e) => e.beaconId.id(beaconId) & e.userId.id(userId),
      )
      .update((o) => o(status: const Value(1)));

  Future<List<CommitmentEntity>> fetchByBeaconId(String beaconId) =>
      _database.managers.beaconCommitments
          .filter((e) => e.beaconId.id(beaconId) & e.status.equals(0))
          .get()
          .then((rows) => rows.map(_toEntity).toList());

  Future<List<CommitmentEntity>> fetchByUserId(String userId) =>
      _database.managers.beaconCommitments
          .filter((e) => e.userId.id(userId) & e.status.equals(0))
          .orderBy((e) => e.updatedAt.desc())
          .get()
          .then((rows) => rows.map(_toEntity).toList());

  static CommitmentEntity _toEntity(BeaconCommitment row) =>
      CommitmentEntity(
        beaconId: row.beaconId,
        userId: row.userId,
        message: row.message,
        status: row.status,
        createdAt: (row.createdAt as PgDateTime).dateTime,
        updatedAt: (row.updatedAt as PgDateTime).dateTime,
      );
}
