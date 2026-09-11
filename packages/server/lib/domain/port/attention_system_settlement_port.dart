/// System-driven settlement for review-opened obligations (not user dismiss/resolve).
abstract class AttentionSystemSettlementPort {
  /// After review window close: per-recipient outcome from [beacon_review_status].
  Future<int> settleReviewObligationsAfterWindowClose(String beaconId);

  /// When review returns to open: prior reviewOpened obligations on this beacon.
  Future<int> supersedeReviewObligationsOnReopen(String beaconId);

  /// After the author (or steward) admits or declines a help offer: settle that
  /// author's `helpOfferSubmitted` obligation and mark the matching receipt seen.
  /// [authorAccountId] is the request author, not necessarily the admitting actor.
  Future<int> settleAuthorHelpOfferSubmitted({
    required String beaconId,
    required String authorAccountId,
    required String helpOffererUserId,
  });

  /// Beacons whose review window row is closed ([beacon_review_window].status = 1).
  Future<List<String>> listBeaconIdsWithClosedReviewWindows();
}
