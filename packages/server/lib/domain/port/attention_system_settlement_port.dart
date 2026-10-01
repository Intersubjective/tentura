/// System-driven settlement for help-offer obligations (not user dismiss/resolve).
abstract class AttentionSystemSettlementPort {
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
}
