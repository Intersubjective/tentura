import 'package:tentura_server/domain/coordination/coordination_response_type.dart';

/// Active help offer slice needed for coordination status derivation (no DB types).
final class CoordinationStatusActiveOffer {
  const CoordinationStatusActiveOffer({
    required this.userId,
    required this.createdAt,
  });

  final String userId;
  final DateTime createdAt;
}

/// Derived beacon coordination status (`beacon.coordination_status` smallint).
///
/// See [help-offer-coordination-feature-design.md] §8 and
/// [deriveBeaconCoordinationStatus].
abstract final class DerivedBeaconCoordinationStatus {
  static const int neutral = 0;
  static const int helpOffersWaitingForReview = 1;
  static const int moreOrDifferentHelpNeeded = 2;
  static const int enoughHelpOffered = 3;
}

/// Deterministic coordination status from active help offers and author responses.
///
/// Rules (design doc §8):
/// 1. No active offers → [DerivedBeaconCoordinationStatus.neutral].
/// 2. Any active offer without an author coordination row →
///    [DerivedBeaconCoordinationStatus.helpOffersWaitingForReview].
/// 3. All offers have responses and any non-`useful` response →
///    [DerivedBeaconCoordinationStatus.moreOrDifferentHelpNeeded].
/// 4. All responses are `useful` → [DerivedBeaconCoordinationStatus.enoughHelpOffered].
///
/// ## Staleness vs design doc §8 rule 3 (future-arch §8.5)
/// The spec narrows staleness to offers **created after**
/// `coordination_status_updated_at` that still lack a response. This function
/// implements the broader shipped rule 2: **any** active offer missing a
/// coordination row yields waiting-for-review, regardless of offer age relative
/// to the last status update. Use [offerUnreviewedForStaleness] for the narrower
/// §8 rule 3 predicate when aligning product behavior.
int deriveBeaconCoordinationStatus({
  required Iterable<CoordinationStatusActiveOffer> activeOffers,
  required Map<String, int> responseTypeByOfferUserId,
}) {
  final offers = activeOffers.toList();
  if (offers.isEmpty) {
    return DerivedBeaconCoordinationStatus.neutral;
  }

  for (final offer in offers) {
    if (!responseTypeByOfferUserId.containsKey(offer.userId)) {
      return DerivedBeaconCoordinationStatus.helpOffersWaitingForReview;
    }
  }

  for (final offer in offers) {
    final responseType = responseTypeByOfferUserId[offer.userId]!;
    if (responseType != CoordinationResponseType.useful.smallintValue) {
      return DerivedBeaconCoordinationStatus.moreOrDifferentHelpNeeded;
    }
  }

  return DerivedBeaconCoordinationStatus.enoughHelpOffered;
}

/// Whether an active offer should push status toward waiting-for-review under
/// design doc §8 rule 3 (staleness / future-arch §8.5).
bool offerUnreviewedForStaleness({
  required DateTime offerCreatedAt,
  required DateTime? coordinationStatusUpdatedAt,
  bool hasAuthorResponse = false,
}) {
  if (hasAuthorResponse) {
    return false;
  }
  final anchor = coordinationStatusUpdatedAt;
  if (anchor == null) {
    return true;
  }
  return offerCreatedAt.isAfter(anchor);
}
