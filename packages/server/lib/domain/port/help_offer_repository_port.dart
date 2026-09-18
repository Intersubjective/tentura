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

  /// Ends the active offer grant without changing its message or exit reason.
  Future<void> deactivate({required String beaconId, required String userId});

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

  /// Sets [roleLabel] on the active offer. Empty/null clears to SQL NULL.
  /// Mutates as [actorUserId] (self, author, or steward).
  Future<void> setRoleLabel({
    required String beaconId,
    required String offerUserId,
    required String actorUserId,
    required String? roleLabel,
  });
}
