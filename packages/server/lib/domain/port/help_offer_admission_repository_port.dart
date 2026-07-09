import 'package:tentura_server/domain/entity/help_offer_admission_event.dart';

abstract class HelpOfferAdmissionRepositoryPort {
  Future<void> record({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    required HelpOfferAdmissionAction action,
    String? reason,
  });

  Future<HelpOfferAdmissionEvent?> latestFor({
    required String beaconId,
    required String offerUserId,
  });

  Future<Map<String, HelpOfferAdmissionEvent>> latestForBeacon(String beaconId);
}
