import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';

abstract class CoordinationRepositoryPort {
  Future<void> upsertResponse({
    required String beaconId,
    required String offerUserId,
    required String authorUserId,
    required int responseType,
  });

  /// Accept admission rows (Arch §5.3 steps b–d): coordination `useful`, room
  /// admission and the `accept` admission event, with [confirmingAuthorId]
  /// (author or steward) recorded as the author/actor. Runs in a mutating
  /// unit for [actorUserId], the authenticated actor, which may be the helper.
  Future<({BeaconStatus status, DateTime? statusChangedAt})> acceptHelpOffer({
    required String beaconId,
    required String offerUserId,
    required String confirmingAuthorId,
    required String actorUserId,
  });

  Future<({BeaconStatus status, DateTime? statusChangedAt})> declineHelpOffer({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    required String reason,
  });

  Future<({BeaconStatus status, DateTime? statusChangedAt})> removeFromRoom({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    required String reason,
  });

  Future<({BeaconStatus status, DateTime? statusChangedAt})>
  beaconStatusSnapshot(
    String beaconId,
  );

  Future<List<HelpOfferWithCoordinationRow>> helpOffersWithCoordination(
    String beaconId, {
    required String viewerId,
  });

  /// Offer user id → `beacon_help_offer_coordination.response_type`.
  Future<Map<String, int>> coordinationResponseTypeByOfferUserId(
    String beaconId,
  );
}
