import 'package:injectable/injectable.dart';
import 'package:drift_postgres/drift_postgres.dart' show PgDateTime;
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/consts/beacon_activity_event_consts.dart';
import 'package:tentura_server/consts/beacon_participant_status_bits.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/coordination/coordination_response_type.dart';
import 'package:tentura_server/domain/entity/beacon_activity_event_entity.dart';
import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';
import 'package:tentura_server/domain/entity/help_offer_admission_event.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';
import 'package:tentura_server/domain/port/user_profile_batch_lookup_port.dart';
import 'package:tentura_server/utils/id.dart';

import '../database/tentura_db.dart';
import 'help_offer_admission_repository.dart';
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

  Future<void> _upsertResponseRaw({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    required int responseType,
  }) => _database
      .into(_database.beaconHelpOfferCoordinations)
      .insert(
        BeaconHelpOfferCoordinationsCompanion.insert(
          offerBeaconId: beaconId,
          offerUserId: offerUserId,
          authorUserId: actorUserId,
          responseType: responseType,
        ),
        onConflict: DoUpdate(
          (_) => BeaconHelpOfferCoordinationsCompanion(
            authorUserId: Value(actorUserId),
            responseType: Value(responseType),
            updatedAt: Value(PgDateTime(DateTime.timestamp())),
          ),
        ),
      );

  Future<void> _inviteOfferUserToBeaconRoomRaw({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
  }) async {
    final existing = await _database.managers.beaconParticipants
        .filter((r) => r.beaconId.id(beaconId) & r.userId.id(offerUserId))
        .getSingleOrNull();
    if (existing == null) {
      await _database.managers.beaconParticipants.create(
        (o) => o(
          createdAt: const Value.absent(),
          updatedAt: const Value.absent(),
          id: generateId('P'),
          beaconId: beaconId,
          userId: offerUserId,
          role: BeaconParticipantRoleBits.helper,
          status: const Value(BeaconParticipantStatusBits.committed),
          roomAccess: const Value(RoomAccessBits.admitted),
        ),
      );
      return;
    }
    await _database.managers.beaconParticipants
        .filter((r) => r.beaconId.id(beaconId) & r.userId.id(offerUserId))
        .update(
          (o) => o(
            roomAccess: const Value(RoomAccessBits.admitted),
            status: const Value(BeaconParticipantStatusBits.committed),
            updatedAt: Value(PgDateTime(DateTime.timestamp())),
          ),
        );
  }

  Future<void> _revokeOfferUserBeaconRoomAccessRaw({
    required String beaconId,
    required String offerUserId,
  }) async {
    final existing = await _database.managers.beaconParticipants
        .filter((r) => r.beaconId.id(beaconId) & r.userId.id(offerUserId))
        .getSingleOrNull();
    if (existing == null) return;
    await _database.managers.beaconParticipants
        .filter((r) => r.beaconId.id(beaconId) & r.userId.id(offerUserId))
        .update(
          (o) => o(
            roomAccess: const Value(RoomAccessBits.none),
            updatedAt: Value(PgDateTime(DateTime.timestamp())),
          ),
        );
  }

  Future<void> _insertParticipantRemovedActivityEvent({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
  }) => _database.managers.beaconActivityEvents.create(
    (o) => o(
      id: Value(BeaconActivityEventEntity.newId),
      beaconId: beaconId,
      visibility: BeaconActivityEventVisibilityBits.room,
      type: BeaconActivityEventTypeBits.participantRemoved,
      actorId: Value(actorUserId),
      targetUserId: Value(offerUserId),
      diff: Value(<String, Object?>{
        'removedUserId': offerUserId,
      }),
      createdAt: const Value.absent(),
    ),
  );

  Future<({BeaconStatus status, DateTime? statusChangedAt})>
  _snapshotAfterAdmissionAction(String beaconId) =>
      beaconStatusSnapshot(beaconId);

  @override
  Future<({BeaconStatus status, DateTime? statusChangedAt})> acceptHelpOffer({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
  }) => _database.withMutatingUser(actorUserId, () async {
    await _upsertResponseRaw(
      beaconId: beaconId,
      offerUserId: offerUserId,
      actorUserId: actorUserId,
      responseType: CoordinationResponseType.useful.smallintValue,
    );
    await _inviteOfferUserToBeaconRoomRaw(
      beaconId: beaconId,
      offerUserId: offerUserId,
      actorUserId: actorUserId,
    );
    await insertHelpOfferAdmissionEvent(
      _database,
      beaconId: beaconId,
      offerUserId: offerUserId,
      actorUserId: actorUserId,
      action: HelpOfferAdmissionAction.accept,
    );
    return _snapshotAfterAdmissionAction(beaconId);
  });

  @override
  Future<({BeaconStatus status, DateTime? statusChangedAt})> declineHelpOffer({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    required String reason,
  }) => _database.withMutatingUser(actorUserId, () async {
    await _upsertResponseRaw(
      beaconId: beaconId,
      offerUserId: offerUserId,
      actorUserId: actorUserId,
      responseType: CoordinationResponseType.notSuitable.smallintValue,
    );
    await insertHelpOfferAdmissionEvent(
      _database,
      beaconId: beaconId,
      offerUserId: offerUserId,
      actorUserId: actorUserId,
      action: HelpOfferAdmissionAction.decline,
      reason: reason,
    );
    return _snapshotAfterAdmissionAction(beaconId);
  });

  @override
  Future<({BeaconStatus status, DateTime? statusChangedAt})> removeFromRoom({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    required String reason,
  }) => _database.withMutatingUser(actorUserId, () async {
    await _revokeOfferUserBeaconRoomAccessRaw(
      beaconId: beaconId,
      offerUserId: offerUserId,
    );
    await insertHelpOfferAdmissionEvent(
      _database,
      beaconId: beaconId,
      offerUserId: offerUserId,
      actorUserId: actorUserId,
      action: HelpOfferAdmissionAction.remove,
      reason: reason,
    );
    await _insertParticipantRemovedActivityEvent(
      beaconId: beaconId,
      offerUserId: offerUserId,
      actorUserId: actorUserId,
    );
    return _snapshotAfterAdmissionAction(beaconId);
  });

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

  Future<Map<String, HelpOfferAdmissionEvent>> _latestAdmissionByOfferUserId(
    String beaconId,
  ) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT DISTINCT ON (beacon_id, offer_user_id)
  id,
  seq,
  beacon_id,
  offer_user_id,
  actor_user_id,
  action,
  reason,
  created_at::text AS created_at
FROM public.beacon_help_offer_admission_event
WHERE beacon_id = $1
ORDER BY beacon_id, offer_user_id, seq DESC
''',
          variables: [Variable<String>(beaconId)],
          readsFrom: {_database.beaconHelpOfferAdmissionEvents},
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('offer_user_id'): HelpOfferAdmissionEvent(
          id: row.read<String>('id'),
          seq: row.read<int>('seq'),
          beaconId: row.read<String>('beacon_id'),
          offerUserId: row.read<String>('offer_user_id'),
          actorUserId: row.read<String>('actor_user_id'),
          action: HelpOfferAdmissionAction.tryFromInt(
            row.read<int>('action'),
          )!,
          reason: row.readNullable<String>('reason'),
          createdAt: DateTime.parse(row.read<String>('created_at')).toUtc(),
        ),
    };
  }

  @override
  Future<({BeaconStatus status, DateTime? statusChangedAt})>
  beaconStatusSnapshot(
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
    final admissions = await _latestAdmissionByOfferUserId(beaconId);
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
      final admission = admissions[row.userId];
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
          admissionAction: admission?.action.smallintValue,
          lastDeclineReason:
              admission?.action == HelpOfferAdmissionAction.decline
              ? admission?.reason
              : null,
          lastRemoveReason: admission?.action == HelpOfferAdmissionAction.remove
              ? admission?.reason
              : null,
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
