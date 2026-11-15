/// The one rule for settling a live «new help offer» obligation the author
/// can no longer act on. `AttentionReconciliationRepository` runs it for one
/// account on reconcile and on every attention read. Migrations (m0315) keep
/// their own frozen copy, so changing the rule never rewrites one.
abstract final class HelpOfferSettlementSql {
  /// `attention_occurrence.event_type` of a new help offer.
  static const helpOfferSubmitted = 'helpOfferSubmitted';

  /// `beacon.status` values that end every question a Request could ask:
  /// cancelled, deleted, closed.
  static const terminalBeaconStatuses = '(1, 2, 6)';

  /// `beacon_commitment_event.kind` values that end a help offer without the
  /// author answering it: withdrawnByHelper, removedFromChat, blockedCleanup.
  static const terminalCommitmentKinds = '(3, 5, 7)';

  /// `beacon_commitment_event.kind` values that mean the author already
  /// answered: acknowledged, acknowledgementSoftened, releasedByAuthor.
  static const answeredCommitmentKinds = '(1, 2, 4)';

  /// `EXISTS` predicate: the helper [userColumn] has a commitment event of one
  /// of [kinds] on Request [beaconColumn] newer than their latest `offered`
  /// (kind 0) event. A re-offer starts a new generation, so history before it
  /// never answers or ends it. Without any `offered` event every event counts.
  static String eventSinceLatestOffer({
    required String beaconColumn,
    required String userColumn,
    required String kinds,
  }) =>
      '''
EXISTS (
  SELECT 1 FROM public.beacon_commitment_event AS ce
  WHERE ce.beacon_id = $beaconColumn
    AND ce.user_id = $userColumn
    AND ce.kind IN $kinds
    AND ce.seq > COALESCE((
      SELECT max(offered.seq) FROM public.beacon_commitment_event AS offered
      WHERE offered.beacon_id = $beaconColumn
        AND offered.user_id = $userColumn
        AND offered.kind = 0
    ), 0)
)''';

  /// Settles stale live help-offer obligations: an answered offer becomes
  /// `resolved`, a withdrawn or missing offer (or an ended Request)
  /// `superseded`; an offer still waiting stays live. Only unsettled
  /// `requires_action` rows are written, so a rerun changes nothing; a row
  /// settled concurrently (dismiss, admit) after the read is never overwritten.
  ///
  /// [accountScope] is a predicate on `outbox` — e.g. `outbox.account_id = $1`,
  /// or `TRUE` for every account.
  static String settleStale({required String accountScope}) =>
      '''
WITH live AS (
  SELECT outbox.id, outbox.beacon_id, outbox.target_entity_id
  FROM public.notification_outbox AS outbox
  JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
  WHERE $accountScope
    AND occ.event_type = '$helpOfferSubmitted'
    AND outbox.requires_action
    AND outbox.settlement_kind IS NULL
    AND outbox.logical_task_key IS NOT NULL
),
judged AS (
  SELECT
    live.id,
    CASE
      WHEN ${eventSinceLatestOffer(beaconColumn: 'live.beacon_id', userColumn: 'live.target_entity_id', kinds: terminalCommitmentKinds)} THEN 'superseded'
      WHEN offer.user_id IS NULL THEN 'superseded'
      WHEN offer.withdraw_reason IS NOT NULL THEN 'superseded'
      WHEN b.status IN $terminalBeaconStatuses THEN 'superseded'
      WHEN ${eventSinceLatestOffer(beaconColumn: 'live.beacon_id', userColumn: 'live.target_entity_id', kinds: answeredCommitmentKinds)} THEN 'resolved'
      WHEN offer.status <> 0 THEN 'resolved'
      ELSE NULL
    END AS settlement
  FROM live
  JOIN public.beacon AS b ON b.id = live.beacon_id
  LEFT JOIN public.beacon_help_offer AS offer
    ON offer.beacon_id = live.beacon_id
   AND offer.user_id = live.target_entity_id
)
UPDATE public.notification_outbox AS outbox
SET
  settlement_kind = judged.settlement,
  settled_at = now(),
  settled_by_user_id = NULL,
  settled_by_occurrence_id = NULL
FROM judged
WHERE outbox.id = judged.id
  AND judged.settlement IS NOT NULL
  AND outbox.settlement_kind IS NULL
''';
}
