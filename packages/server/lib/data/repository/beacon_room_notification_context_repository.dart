import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/domain/commitment/commitment_state.dart';
import 'package:tentura_server/domain/entity/beacon_notification_context.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_context_port.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';

import '../database/tentura_db.dart';

@LazySingleton(as: BeaconRoomNotificationContextPort)
class BeaconRoomNotificationContextRepository
    implements BeaconRoomNotificationContextPort {
  const BeaconRoomNotificationContextRepository(
    this._room,
    this._db,
    this._helpOffers,
    this._commitments,
  );

  final BeaconRoomRepositoryPort _room;
  final TenturaDb _db;
  final HelpOfferRepositoryPort _helpOffers;
  final CommitmentRepositoryPort _commitments;

  @override
  Future<BeaconNotificationContext> loadContextForBeacon(
    String beaconId,
  ) async {
    final author = await _room.beaconAuthorUserId(beaconId);
    final stewards = await _room.listStewardUserIds(beaconId);
    final admitted = await _room.listAdmittedUserIds(beaconId);
    final helpOfferUserIds = await _activeHelpOfferUserIds(beaconId);
    final requestParticipantUserIds =
        await _activeRequestParticipantUserIds(beaconId);
    final planParticipantUserIds = await _activePlanParticipantUserIds(beaconId);
    final inboxStances = await _inboxStanceUserIds(beaconId);

    return BeaconNotificationContext(
      beaconAuthorId: author ?? '',
      admittedUserIds: admitted.toSet(),
      stewardUserIds: stewards.toSet(),
      activeHelpOfferUserIds: helpOfferUserIds,
      activeRequestParticipantUserIds: requestParticipantUserIds,
      activePlanParticipantUserIds: planParticipantUserIds,
      inboxStanceUserIds: inboxStances,
    );
  }

  Future<Set<String>> _inboxStanceUserIds(String beaconId) async {
    final rows =
        await (_db.select(_db.inboxItems)
              ..where((item) => item.beaconId.equals(beaconId))
              ..where((item) => item.status.isIn(const [0, 1])))
            .get();
    return rows.map((row) => row.userId).toSet();
  }

  Future<Set<String>> _activeHelpOfferUserIds(String beaconId) async {
    final offers = await _helpOffers.fetchByBeaconId(beaconId);
    return {
      for (final offer in offers)
        if (offer.userId.isNotEmpty) offer.userId,
    };
  }

  Future<Set<String>> _activeRequestParticipantUserIds(String beaconId) async {
    final byUser = await _commitments.eventsByUser(beaconId);
    final offers = await _helpOffers.fetchByBeaconId(beaconId);
    final activeByUser = {
      for (final offer in offers)
        if (_isActiveOffer(offer)) offer.userId: true,
    };
    return {
      for (final entry in byUser.entries)
        if (hasCurrentStake(
          entry.value,
          hasActiveOffer: activeByUser[entry.key] ?? false,
        ))
          entry.key,
    };
  }

  Future<Set<String>> _activePlanParticipantUserIds(String beaconId) async {
    final rows =
        await (_db.select(_db.coordinationItems)
              ..where((t) => t.beaconId.equals(beaconId))
              ..where((t) => t.kind.equals(coordinationItemKindPlan))
              ..where((t) => t.published.equals(true))
              ..where(
                (t) =>
                    t.status.equals(coordinationItemStatusOpen) |
                    t.status.equals(coordinationItemStatusAccepted),
              ))
            .get();
    final out = <String>{};
    for (final row in rows) {
      if (row.creatorId.isNotEmpty) {
        out.add(row.creatorId);
      }
      final target = row.targetPersonId;
      if (target != null && target.isNotEmpty) {
        out.add(target);
      }
      final accepted = row.acceptedById;
      if (accepted != null && accepted.isNotEmpty) {
        out.add(accepted);
      }
    }
    return out;
  }

  static bool _isActiveOffer(HelpOfferEntity offer) => offer.status == 0;
}
