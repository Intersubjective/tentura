import 'package:injectable/injectable.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/entity/gql_public/help_offer_with_coordination_row.dart';
import 'package:tentura_server/domain/port/coordination_repository_port.dart';

@Injectable(
  as: CoordinationRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class CoordinationRepositoryMock implements CoordinationRepositoryPort {
  static const _openStatus = (
    status: BeaconStatus.open,
    statusChangedAt: null,
  );

  @override
  Future<void> upsertResponse({
    required String beaconId,
    required String offerUserId,
    required String authorUserId,
    required int responseType,
  }) => Future.value();

  @override
  Future<({BeaconStatus status, DateTime? statusChangedAt})> acceptHelpOffer({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
  }) => Future.value(_openStatus);

  @override
  Future<({BeaconStatus status, DateTime? statusChangedAt})> declineHelpOffer({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    required String reason,
  }) => Future.value(_openStatus);

  @override
  Future<({BeaconStatus status, DateTime? statusChangedAt})> removeFromRoom({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    required String reason,
  }) => Future.value(_openStatus);

  @override
  Future<({BeaconStatus status, DateTime? statusChangedAt})>
  beaconStatusSnapshot(String beaconId) => Future.value(_openStatus);

  @override
  Future<List<HelpOfferWithCoordinationRow>> helpOffersWithCoordination(
    String beaconId, {
    required String viewerId,
  }) => Future.value(const []);

  @override
  Future<Map<String, int>> coordinationResponseTypeByOfferUserId(
    String beaconId,
  ) => Future.value(const {});
}
