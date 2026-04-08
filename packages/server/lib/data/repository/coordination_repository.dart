import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart';

import '../database/tentura_db.dart';
import 'user_presence_repository.dart';

@Injectable(
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class CoordinationRepository {
  const CoordinationRepository(
    this._database,
    this._userPresenceRepository,
  );

  final TenturaDb _database;

  final UserPresenceRepository _userPresenceRepository;

  Future<void> deleteForCommit({
    required String beaconId,
    required String userId,
  }) => _database.managers.beaconCommitmentCoordinations
      .filter(
        (e) => e.commitBeaconId.id(beaconId) & e.commitUserId.id(userId),
      )
      .delete();

  Future<void> upsertResponse({
    required String beaconId,
    required String commitUserId,
    required String authorUserId,
    required int responseType,
  }) => _database.into(_database.beaconCommitmentCoordinations).insert(
    BeaconCommitmentCoordinationsCompanion.insert(
      commitBeaconId: beaconId,
      commitUserId: commitUserId,
      authorUserId: authorUserId,
      responseType: responseType,
    ),
    onConflict: DoUpdate(
      (_) => BeaconCommitmentCoordinationsCompanion(
        authorUserId: Value(authorUserId),
        responseType: Value(responseType),
        updatedAt: Value(PgDateTime(DateTime.timestamp())),
      ),
    ),
  );

  Future<Map<String, int>> _responseTypesByUserId(String beaconId) async {
    final rows = await _database.managers.beaconCommitmentCoordinations
        .filter((e) => e.commitBeaconId.id(beaconId))
        .get();
    return {for (final r in rows) r.commitUserId: r.responseType};
  }

  Future<({int coordinationStatus, DateTime? coordinationStatusUpdatedAt})>
  beaconCoordinationSnapshot(String beaconId) async {
    final b = await _database.managers.beacons
        .filter((e) => e.id.equals(beaconId))
        .getSingleOrNull();
    if (b == null) {
      return (coordinationStatus: 0, coordinationStatusUpdatedAt: null);
    }
    return (
      coordinationStatus: b.coordinationStatus,
      coordinationStatusUpdatedAt: b.coordinationStatusUpdatedAt?.dateTime,
    );
  }

  Future<void> setBeaconCoordinationFields({
    required String beaconId,
    required int coordinationStatus,
  }) => _database.managers.beacons
      .filter((e) => e.id.equals(beaconId))
      .update(
        (o) => o(
          coordinationStatus: Value(coordinationStatus),
          coordinationStatusUpdatedAt: Value(PgDateTime(DateTime.timestamp())),
        ),
      );

  /// Deterministic coordination status from active commits + author responses.
  Future<void> recomputeAndPersistBeaconCoordinationStatus(
    String beaconId,
  ) async {
    final beacon = await _database.managers.beacons
        .filter((e) => e.id.equals(beaconId))
        .getSingleOrNull();
    if (beacon == null) return;

    final active = await _database.managers.beaconCommitments
        .filter((e) => e.beaconId.id(beaconId) & e.status.equals(0))
        .get();

    if (active.isEmpty) {
      await setBeaconCoordinationFields(
        beaconId: beaconId,
        coordinationStatus: 0,
      );
      return;
    }

    final coords = await _responseTypesByUserId(beaconId);
    for (final c in active) {
      if (!coords.containsKey(c.userId)) {
        await setBeaconCoordinationFields(
          beaconId: beaconId,
          coordinationStatus: 1,
        );
        return;
      }
    }

    for (final c in active) {
      final rt = coords[c.userId]!;
      if (rt != 0) {
        await setBeaconCoordinationFields(
          beaconId: beaconId,
          coordinationStatus: 2,
        );
        return;
      }
    }

    await setBeaconCoordinationFields(
      beaconId: beaconId,
      coordinationStatus: 3,
    );
  }

  Future<List<Map<String, dynamic>>> commitmentsWithCoordination(
    String beaconId,
  ) async {
    final rows = await _database.managers.beaconCommitments
        .filter((e) => e.beaconId.id(beaconId))
        .orderBy((e) => e.updatedAt.desc())
        .get();

    final coords = await _responseTypesByUserId(beaconId);

    final out = <Map<String, dynamic>>[];
    for (final row in rows) {
      final user = await _database.managers.users
          .filter((e) => e.id.equals(row.userId))
          .getSingle();
      Map<String, dynamic>? imageMap;
      final imageId = user.imageId;
      if (imageId != null) {
        final image = await _database.managers.images
            .filter((e) => e.id.equals(imageId))
            .getSingleOrNull();
        if (image != null) {
          imageMap = {
            'id': image.id.toString(),
            'hash': image.hash,
            'height': image.height,
            'width': image.width,
            'author_id': image.authorId,
            'created_at': image.createdAt.dateTime.toUtc().toIso8601String(),
          };
        }
      }

      final presence = await _userPresenceRepository.get(user.id);
      out.add({
        'beaconId': row.beaconId,
        'userId': row.userId,
        'message': row.message,
        'helpType': row.helpType,
        'status': row.status,
        'uncommitReason': row.uncommitReason,
        'createdAt': row.createdAt.dateTime.toUtc().toIso8601String(),
        'updatedAt': row.updatedAt.dateTime.toUtc().toIso8601String(),
        'responseType': coords[row.userId],
        'user': <String, dynamic>{
          'id': user.id,
          'title': user.title,
          'description': user.description,
          'my_vote': null,
          'image': imageMap, // nullable; matches Hasura `user.image`
          'scores': <Map<String, dynamic>>[],
          'user_presence': presence == null
              ? null
              : {
                  'last_seen_at':
                      presence.lastSeenAt.toUtc().toIso8601String(),
                  'status': presence.status.index,
                },
        },
      });
    }
    return out;
  }
}
