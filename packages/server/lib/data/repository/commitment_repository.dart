import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/domain/entity/commitment_entity.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: CommitmentRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class CommitmentRepository implements CommitmentRepositoryPort {
  const CommitmentRepository(this._database);

  final TenturaDb _database;

  @override
  Future<void> upsert({
    required String beaconId,
    required String userId,
    String message = '',
    String? helpType,
    int status = 0,
  }) => _database.withMutatingUser(userId, () async {
    await _database.into(_database.beaconCommitments).insert(
      BeaconCommitmentsCompanion.insert(
        beaconId: beaconId,
        userId: userId,
        message: Value(message),
        helpType: Value(helpType),
        status: Value(status),
      ),
      onConflict: DoUpdate(
        (_) => BeaconCommitmentsCompanion(
          message: Value(message),
          helpType: Value(helpType),
          uncommitReason: status == 0
              ? const Value(null)
              : const Value.absent(),
          status: Value(status),
          updatedAt: Value(PgDateTime(DateTime.timestamp())),
        ),
      ),
    );
  });

  @override
  Future<void> withdraw({
    required String beaconId,
    required String userId,
    required String uncommitReason,
    String message = '',
  }) => _database.withMutatingUser(userId, () async {
    await _database.managers.beaconCommitments
        .filter(
          (e) => e.beaconId.id(beaconId) & e.userId.id(userId),
        )
        .update(
          (o) => o(
            status: const Value(1),
            message: Value(message),
            uncommitReason: Value(uncommitReason),
            updatedAt: Value(PgDateTime(DateTime.timestamp())),
          ),
        );
  });

  @override
  Future<List<CommitmentEntity>> fetchByBeaconId(String beaconId) =>
      _database.managers.beaconCommitments
          .filter((e) => e.beaconId.id(beaconId) & e.status.equals(0))
          .get()
          .then((rows) => rows.map(_toEntity).toList());

  /// Active and withdrawn rows (status 0 and 1). Used for forward involvement.
  @override
  Future<List<CommitmentEntity>> fetchAllByBeaconId(String beaconId) =>
      _database.managers.beaconCommitments
          .filter((e) => e.beaconId.id(beaconId))
          .get()
          .then((rows) => rows.map(_toEntity).toList());

  @override
  Future<List<CommitmentEntity>> fetchByUserId(String userId) =>
      _database.managers.beaconCommitments
          .filter((e) => e.userId.id(userId) & e.status.equals(0))
          .orderBy((e) => e.updatedAt.desc())
          .get()
          .then((rows) => rows.map(_toEntity).toList());

  @override
  Future<bool> hasActiveCommitment({
    required String beaconId,
    required String userId,
  }) async {
    final row = await _database.managers.beaconCommitments
        .filter(
          (e) => e.beaconId.id(beaconId) & e.userId.id(userId) & e.status.equals(0),
        )
        .getSingleOrNull();
    return row != null;
  }

  static CommitmentEntity _toEntity(BeaconCommitment row) =>
      CommitmentEntity(
        beaconId: row.beaconId,
        userId: row.userId,
        message: row.message,
        status: row.status,
        helpType: row.helpType,
        uncommitReason: row.uncommitReason,
        createdAt: row.createdAt.dateTime,
        updatedAt: row.updatedAt.dateTime,
      );
}
