/// System-driven settlement for review-opened obligations (not user dismiss/resolve).
abstract class AttentionSystemSettlementPort {
  /// After review window close: per-recipient outcome from [beacon_review_status].
  Future<int> settleReviewObligationsAfterWindowClose(String beaconId);

  /// When review returns to open: prior reviewOpened obligations on this beacon.
  Future<int> supersedeReviewObligationsOnReopen(String beaconId);

  /// After one reviewer sends their package ([beacon_review_status] = 2): settle
  /// that reviewer's own unsettled `reviewOpened` receipt as resolved.
  Future<int> settleReviewerObligationOnPackageSend({
    required String beaconId,
    required String reviewerAccountId,
  });

  /// After the author (or steward) admits or declines a help offer: settle that
  /// author's `helpOfferSubmitted` obligation and mark the matching receipt seen.
  /// [authorAccountId] is the request author, not necessarily the admitting actor.
  Future<int> settleAuthorHelpOfferSubmitted({
    required String beaconId,
    required String authorAccountId,
    required String helpOffererUserId,
  });

  /// Terminal invalidation of one help offer (the helper withdrew, or the
  /// author removed them from the room): the author's `helpOfferSubmitted`
  /// obligation ends as `superseded` — the question it asked is gone, and it
  /// was never answered, so it must not be recorded as `resolved`.
  Future<int> supersedeAuthorHelpOfferSubmitted({
    required String beaconId,
    required String authorAccountId,
    required String helpOffererUserId,
  });

  /// Request close: every still-live `helpOfferSubmitted` obligation on this
  /// beacon ends as `superseded`. The author closed the Request, so no offer on
  /// it can still be answered.
  Future<int> supersedeAuthorHelpOfferObligationsOnBeaconClose(String beaconId);

  /// Beacons whose review window row is closed ([beacon_review_window].status = 1).
  Future<List<String>> listBeaconIdsWithClosedReviewWindows();
}
