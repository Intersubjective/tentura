import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart' show PgDateTime;
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';

import '../database/tentura_db.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';
import 'user_profile_batch_lookup.dart';

@Injectable(
  as: CoordinationRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class CoordinationRepository implements CoordinationRepositoryPort {
  CoordinationRepository(
    this._database,
    this._userProfileBatchLookup,
    this._voteUserFriendshipLookup,
  );

  final TenturaDb _database;

  final UserProfileBatchLookup _userProfileBatchLookup;

  final VoteUserFriendshipLookupPort _voteUserFriendshipLookup;

  @override
  Future<void> deleteForCommit({
    required String beaconId,
    required String userId,
  }) => _database.managers.beaconHelpOfferCoordinations
      .filter(
        (e) => e.offerBeaconId.id(beaconId) & e.offerUserId.id(userId),
      )
      .delete();

  @override
  Future<void> upsertResponse({
    required String beaconId,
    required String offerUserId,
    required String authorUserId,
    required int responseType,
  }) => _database
      .into(_database.beaconHelpOfferCoordinations)
      .insert(
        BeaconHelpOfferCoordinationsCompanion.insert(
          offerBeaconId: beaconId,
          offerUserId: offerUserId,
          authorUserId: authorUserId,
          responseType: responseType,
        ),
        onConflict: DoUpdate(
          (_) => BeaconHelpOfferCoordinationsCompanion(
            authorUserId: Value(authorUserId),
            responseType: Value(responseType),
            updatedAt: Value(PgDateTime(DateTime.timestamp())),
          ),
        ),
      );

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
    final rows = await _database.managers.beaconHelpOfferCoordinations
        .filter((e) => e.offerBeaconId.id(beaconId))
        .get();
    return {
      for (final r in rows)
        r.offerUserId: (
          responseType: r.responseType,
          responseUpdatedAt: r.updatedAt.dateTime,
          authorUserId: r.authorUserId,
        ),
    };
  }

  @override
  Future<({BeaconStatus status, DateTime? statusChangedAt})> beaconStatusSnapshot(
    String beaconId,
  ) async {
    final b = await _database.managers.beacons
        .filter((e) => e.id.equals(beaconId))
        .getSingleOrNull();
    if (b == null) {
      return (status: BeaconStatus.open, statusChangedAt: null);
    }
    return (
      status: BeaconStatus.fromSmallint(b.status),
      statusChangedAt: b.statusChangedAt?.dateTime,
    );
  }

  @override
  Future<List<HelpOfferWithCoordinationRow>> helpOffersWithCoordination(
    String beaconId, {
    required String viewerId,
  }) async {
    final rows = await _database.managers.beaconHelpOffers
        .filter((e) => e.beaconId.id(beaconId))
        .orderBy((e) => e.updatedAt.desc())
        .get();

    final coords = await _coordinationByCommitUserId(beaconId);
    final reciprocal = await _voteUserFriendshipLookup
        .reciprocalPositivePeerIds(
          viewerId: viewerId,
          peerIds: rows.map((r) => r.userId),
        );

    final participantRows = await _database.managers.beaconParticipants
        .filter((p) => p.beaconId.id(beaconId))
        .get();
    final roomAccessByUserId = <String, int>{
      for (final p in participantRows) p.userId: p.roomAccess,
    };

    final userIds = rows.map((r) => r.userId).toList();
    final usersById = await _userProfileBatchLookup.userPublicRecordsByIds(
      ids: userIds,
      reciprocalPeerIds: reciprocal,
    );

    final out = <HelpOfferWithCoordinationRow>[];
    for (final row in rows) {
      final userPublic = usersById[row.userId];
      if (userPublic == null) {
        throw IdNotFoundException(id: row.userId);
      }
      final coord = coords[row.userId];
      out.add(
        HelpOfferWithCoordinationRow(
          beaconId: row.beaconId,
          userId: row.userId,
          message: row.message,
          status: row.status,
          createdAt: row.createdAt.dateTime.toUtc(),
          updatedAt: row.updatedAt.dateTime.toUtc(),
          user: userPublic,
          helpType: row.helpType,
          withdrawReason: row.withdrawReason,
          responseType: coord?.responseType,
          responseUpdatedAt: coord?.responseUpdatedAt.toUtc(),
          responseAuthorUserId: coord?.authorUserId,
          roomAccess: roomAccessByUserId[row.userId],
        ),
      );
    }
    return out;
  }

  @override
  Future<Map<String, int>> coordinationResponseTypeByOfferUserId(
    String beaconId,
  ) async {
    final rows = await _database.managers.beaconHelpOfferCoordinations
        .filter((e) => e.offerBeaconId.id(beaconId))
        .get();
    return {for (final r in rows) r.offerUserId: r.responseType};
  }
}
