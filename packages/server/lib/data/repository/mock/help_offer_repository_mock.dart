import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';

@Injectable(
  as: HelpOfferRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class HelpOfferRepositoryMock implements HelpOfferRepositoryPort {
  @override
  Future<void> upsert({
    required String beaconId,
    required String userId,
    String message = '',
    List<String>? helpTypes,
    int status = 0,
    int offerKind = 0,
  }) => Future.value();

  @override
  Future<void> withdraw({
    required String beaconId,
    required String userId,
    required String withdrawReason,
    String message = '',
  }) => Future.value();

  @override
  Future<void> deactivate({required String beaconId, required String userId}) =>
      Future.value();

  @override
  Future<List<HelpOfferEntity>> fetchByBeaconId(String beaconId) =>
      Future.value(const []);

  @override
  Future<List<HelpOfferEntity>> fetchAllByBeaconId(String beaconId) =>
      Future.value(const []);

  @override
  Future<List<HelpOfferEntity>> fetchByUserId(String userId) =>
      Future.value(const []);

  @override
  Future<bool> hasActiveHelpOffer({
    required String beaconId,
    required String userId,
  }) => Future.value(false);

  @override
  Future<List<String>> fetchActiveHelpTypes({
    required String beaconId,
    required String userId,
  }) => Future.value(const []);

  @override
  Future<void> setRoleLabel({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    required String? roleLabel,
  }) => Future.value();
}
