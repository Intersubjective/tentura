import 'package:tentura_server/domain/entity/help_offer_entity.dart';

abstract class HelpOfferRepositoryPort {
  Future<void> upsert({
    required String beaconId,
    required String userId,
    String message = '',
    List<String>? helpTypes,
    int status = 0,
    int offerKind = 0,
  });

  Future<void> withdraw({
    required String beaconId,
    required String userId,
    required String withdrawReason,
    String message = '',
  });

  Future<List<HelpOfferEntity>> fetchByBeaconId(String beaconId);

  Future<List<HelpOfferEntity>> fetchAllByBeaconId(String beaconId);

  Future<List<HelpOfferEntity>> fetchByUserId(String userId);

  Future<bool> hasActiveHelpOffer({
    required String beaconId,
    required String userId,
  });

  /// Decoded help-type slugs from the subject's active offer on [beaconId].
  Future<List<String>> fetchActiveHelpTypes({
    required String beaconId,
    required String userId,
  });
}
