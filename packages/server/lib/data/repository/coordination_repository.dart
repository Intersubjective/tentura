import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart';

import 'package:tentura_server/domain/entity/gql_public/commitment_with_coordination_row.dart';
import 'package:tentura_server/domain/entity/gql_public/image_public_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_presence_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/user_presence_repository_port.dart';

import '../database/tentura_db.dart';
import 'vote_user_friendship_lookup.dart';

@Injectable(
  as: CoordinationRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class CoordinationRepository implements CoordinationRepositoryPort {
  CoordinationRepository(
    this._database,
    this._userPresenceRepository,
    this._voteUserFriendshipLookup,
  );

  final TenturaDb _database;

  final UserPresenceRepositoryPort _userPresenceRepository;

  final VoteUserFriendshipLookup _voteUserFriendshipLookup;

  @override
  Future<void> deleteForCommit({
    required String beaconId,
    required String userId,
  }) => _database.managers.beaconCommitmentCoordinations
      .filter(
        (e) => e.commitBeaconId.id(beaconId) & e.commitUserId.id(userId),
      )
      .delete();

  @override
  Future<void> upsertResponse({
    required String beaconId,
    required String commitUserId,
    required String authorUserId,
    required int responseType,
  }) => _database
      .into(_database.beaconCommitmentCoordinations)
      .insert(
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

  /// Per active commitment user: author response type + when it last changed + author id.
  Future<
    Map<
      String,
      ({
        int responseType,
        DateTime responseUpdatedAt,
        String authorUserId,
      })
    >
  >
  _coordinationByCommitUserId(String beaconId) async {
    final rows = await _database.managers.beaconCommitmentCoordinations
        .filter((e) => e.commitBeaconId.id(beaconId))
        .get();
    return {
      for (final r in rows)
        r.commitUserId: (
          responseType: r.responseType,
          responseUpdatedAt: r.updatedAt.dateTime,
          authorUserId: r.authorUserId,
        ),
    };
  }

  @override
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

  @override
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
  @override
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

    final coords = await _coordinationByCommitUserId(beaconId);
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
      final rt = coords[c.userId]!.responseType;
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

  @override
  Future<List<CommitmentWithCoordinationRow>> commitmentsWithCoordination(
    String beaconId, {
    required String viewerId,
  }) async {
    final rows = await _database.managers.beaconCommitments
        .filter((e) => e.beaconId.id(beaconId))
        .orderBy((e) => e.updatedAt.desc())
        .get();

    final coords = await _coordinationByCommitUserId(beaconId);
    final reciprocal = await _voteUserFriendshipLookup
        .reciprocalPositivePeerIds(
          viewerId: viewerId,
          peerIds: rows.map((r) => r.userId),
        );

    final out = <CommitmentWithCoordinationRow>[];
    for (final row in rows) {
      final user = await _database.managers.users
          .filter((e) => e.id.equals(row.userId))
          .getSingle();
      ImagePublicRecord? imageRecord;
      final imageId = user.imageId;
      if (imageId != null) {
        final image = await _database.managers.images
            .filter((e) => e.id.equals(imageId))
            .getSingleOrNull();
        if (image != null) {
          imageRecord = ImagePublicRecord(
            id: image.id.toString(),
            hash: image.hash,
            height: image.height,
            width: image.width,
            authorId: image.authorId,
            createdAt: image.createdAt.dateTime.toUtc(),
          );
        }
      }

      final presence = await _userPresenceRepository.get(user.id);
      final coord = coords[row.userId];
      final userPresence = presence == null
          ? null
          : UserPresenceRecord(
              lastSeenAt: presence.lastSeenAt,
              status: presence.status.index,
            );
      final userPublic = UserPublicRecord(
        id: user.id,
        title: user.title,
        description: user.description,
        isMutualFriend: reciprocal.contains(user.id),
        image: imageRecord,
        userPresence: userPresence,
      );
      out.add(
        CommitmentWithCoordinationRow(
          beaconId: row.beaconId,
          userId: row.userId,
          message: row.message,
          status: row.status,
          createdAt: row.createdAt.dateTime.toUtc(),
          updatedAt: row.updatedAt.dateTime.toUtc(),
          user: userPublic,
          helpType: row.helpType,
          uncommitReason: row.uncommitReason,
          responseType: coord?.responseType,
          responseUpdatedAt: coord?.responseUpdatedAt.toUtc(),
          responseAuthorUserId: coord?.authorUserId,
        ),
      );
    }
    return out;
  }
}
