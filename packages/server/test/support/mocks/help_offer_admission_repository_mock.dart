import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/help_offer_admission_event.dart';
import 'package:tentura_server/domain/port/help_offer_admission_repository_port.dart';

@Injectable(
  as: HelpOfferAdmissionRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class HelpOfferAdmissionRepositoryMock
    implements HelpOfferAdmissionRepositoryPort {
  @override
  Future<void> record({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    required HelpOfferAdmissionAction action,
    String? reason,
  }) => Future.value();

  @override
  Future<HelpOfferAdmissionEvent?> latestFor({
    required String beaconId,
    required String offerUserId,
  }) => Future.value();

  @override
  Future<Map<String, HelpOfferAdmissionEvent>> latestForBeacon(
    String beaconId,
  ) => Future.value(const {});
}
