/// System-driven settlement of attention (not user dismiss/resolve): help-offer
/// obligations, and the optional author-invite update once it is answered.
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

  /// Post→Request budding (plan C2): an author invitation ended — accepted,
  /// declined, withdrawn, superseded, expired or removed by a block — so the
  /// invitee's `authorInviteReceived` receipts on [beaconId] stop asking for
  /// attention: `cleared_at` and `seen_at` are set. Not a visible event.
  /// Returns the number of receipts cleared; repeating it is a no-op.
  Future<int> clearAuthorInviteReceived({
    required String beaconId,
    required String inviteeId,
  });

  /// The invitee took back the decline of [inviteId]: their
  /// `authorInviteReceived` receipt for that invite asks for an answer again
  /// (no new event, so no new notification), and the inviter's
  /// `authorInviteDeclined` receipt stops asking for attention.
  Future<void> reverseAuthorInviteDeclineReceipts({
    required String inviteId,
    required String beaconId,
    required String inviterId,
    required String inviteeId,
  });
}
