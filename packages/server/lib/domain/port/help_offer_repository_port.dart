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

    /// Actor of the mutating unit (default: `userId`); pass the authenticated
    /// actor when someone else's offer is withdrawn inside their unit of work.
    String? mutatingUserId,
  });

  /// Ends the active offer grant without changing its message or exit reason.
  Future<void> deactivate({required String beaconId, required String userId});

  /// Re-activates an offer that [deactivate] ended without an exit reason
  /// (an author removal), when the author lets the helper back in. A
  /// withdrawn offer (it has a `withdraw_reason`) is left alone.
  Future<void> reactivate({required String beaconId, required String userId});

  Future<List<HelpOfferEntity>> fetchByBeaconId(String beaconId);

  /// [fetchByBeaconId] of each of [beaconIds], keyed by beacon id, read in
  /// one query; a Request without active offers has no entry.
  Future<Map<String, List<HelpOfferEntity>>> fetchByBeaconIds(
    Iterable<String> beaconIds,
  );

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
