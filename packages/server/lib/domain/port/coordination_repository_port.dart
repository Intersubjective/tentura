import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';

abstract class CoordinationRepositoryPort {
  Future<void> deleteForCommit({
    required String beaconId,
    required String userId,
  });

  Future<void> upsertResponse({
    required String beaconId,
    required String offerUserId,
    required String authorUserId,
    required int responseType,
  });

  Future<({int coordinationStatus, DateTime? coordinationStatusUpdatedAt})>
      beaconCoordinationSnapshot(String beaconId);

  Future<void> setBeaconCoordinationFields({
    required String beaconId,
    required int coordinationStatus,
  });

  Future<List<HelpOfferWithCoordinationRow>> helpOffersWithCoordination(
    String beaconId, {
    required String viewerId,
  });

  /// Offer user id → `beacon_help_offer_coordination.response_type`.
  Future<Map<String, int>> coordinationResponseTypeByOfferUserId(
    String beaconId,
  );
}
