import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/attention/attention_reconciliation_models.dart';
import 'package:tentura_server/domain/port/attention_reconciliation_port.dart';

import '../database/tentura_db.dart';

/// U12 / D15 — the SQL side of "Reset counters".
///
/// It generalises `settleReviewObligationsAfterWindowClose` rather than
/// standing a second mechanism beside it. m0203 (A6) dropped the review
/// tables and retired every live review obligation, so the review-era
/// members below are inert (nothing to settle, nothing to backfill); A18
/// deletes those call paths.
///
/// Three properties are load-bearing and each has a test that fails when the
/// clause is removed:
///
/// * every statement is scoped by `account_id = $1`, so reconciliation cannot
///   reach another account's rows even if a caller wanted it to;
/// * only `requires_action` rows are read or written — `cleared_at`, `seen_at`,
///   `inbox_item` and the occurrence log are never in a target list;
/// * a receipt the account settled itself (`settled_by_user_id = account`) is
///   never re-created, so repair cannot resurrect a person's own act.
@Singleton(as: AttentionReconciliationPort)
class AttentionReconciliationRepository implements AttentionReconciliationPort {
  const AttentionReconciliationRepository(this._database);

  final TenturaDb _database;

  static const _helpOfferSubmitted = 'helpOfferSubmitted';

  /// `beacon.status` values that end every question a Request could ask:
  /// cancelled, deleted, closed.
  static const _terminalBeaconStatuses = '(1, 2, 6)';

  /// `beacon_commitment_event.kind` values that end a help offer without the
  /// author answering it: withdrawnByHelper, removedFromChat, blockedCleanup.
  static const _terminalCommitmentKinds = '(3, 5, 7)';

  /// `beacon_commitment_event.kind` values that mean the author already
  /// answered: acknowledged, acknowledgementSoftened, releasedByAuthor.
  static const _answeredCommitmentKinds = '(1, 2, 4)';

  @override
  Future<int> settleObsoleteHelpOfferObligations({
    required String accountId,
  }) => _database.customUpdate(
    '''
WITH live AS (
  SELECT outbox.id, outbox.beacon_id, outbox.target_entity_id
  FROM public.notification_outbox AS outbox
  JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
  WHERE outbox.account_id = \$1
    AND occ.event_type = \$2
    AND outbox.requires_action
    AND outbox.settlement_kind IS NULL
    AND outbox.logical_task_key IS NOT NULL
),
judged AS (
  SELECT
    live.id,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM public.beacon_commitment_event AS ce
        WHERE ce.beacon_id = live.beacon_id
          AND ce.user_id = live.target_entity_id
          AND ce.kind IN $_terminalCommitmentKinds
      ) THEN 'superseded'
      WHEN offer.user_id IS NULL THEN 'superseded'
      WHEN offer.withdraw_reason IS NOT NULL THEN 'superseded'
      WHEN b.status IN $_terminalBeaconStatuses THEN 'superseded'
      WHEN EXISTS (
        SELECT 1 FROM public.beacon_commitment_event AS ce
        WHERE ce.beacon_id = live.beacon_id
          AND ce.user_id = live.target_entity_id
          AND ce.kind IN $_answeredCommitmentKinds
      ) THEN 'resolved'
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
''',
    variables: [
      Variable<String>(accountId),
      const Variable<String>(_helpOfferSubmitted),
    ],
    updateKind: UpdateKind.update,
  );

  /// Inert post-m0203: no review windows or review statuses exist, so no
  /// review obligation can be obsolete. A18 deletes this call path.
  @override
  Future<int> settleObsoleteReviewObligations({required String accountId}) =>
      Future.value(0);

  @override
  Future<List<ReconcilableHelpOfferTask>> listUnbackedHelpOfferTasks({
    required String accountId,
  }) async {
    final rows = await _database
        .customSelect(
          '''
SELECT
  offer.beacon_id AS beacon_id,
  offer.user_id AS help_offerer_id,
  b.user_id AS author_id,
  (
    SELECT COALESCE(MAX(prior.lifecycle_generation), 0)
    FROM public.notification_outbox AS prior
    JOIN public.attention_occurrence AS occ ON occ.id = prior.occurrence_id
    WHERE prior.account_id = \$1
      AND occ.event_type = \$2
      AND prior.beacon_id = offer.beacon_id
      AND prior.target_entity_id = offer.user_id
  ) + 1 AS next_generation
FROM public.beacon_help_offer AS offer
JOIN public.beacon AS b ON b.id = offer.beacon_id
WHERE b.user_id = \$1
  AND offer.status = 0
  AND offer.withdraw_reason IS NULL
  AND b.status NOT IN $_terminalBeaconStatuses
  AND NOT EXISTS (
    SELECT 1 FROM public.beacon_commitment_event AS ce
    WHERE ce.beacon_id = offer.beacon_id
      AND ce.user_id = offer.user_id
      AND ce.kind IN $_terminalCommitmentKinds
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.beacon_commitment_event AS ce
    WHERE ce.beacon_id = offer.beacon_id
      AND ce.user_id = offer.user_id
      AND ce.kind IN $_answeredCommitmentKinds
  )
  AND NOT EXISTS (
    SELECT 1
    FROM public.notification_outbox AS nb
    JOIN public.attention_occurrence AS occ ON occ.id = nb.occurrence_id
    WHERE nb.account_id = \$1
      AND occ.event_type = \$2
      AND nb.beacon_id = offer.beacon_id
      AND nb.target_entity_id = offer.user_id
      AND nb.requires_action
      AND (
        nb.settlement_kind IS NULL
        OR nb.settled_by_user_id IS NOT NULL
      )
  )
ORDER BY offer.beacon_id, offer.user_id
''',
          variables: [
            Variable<String>(accountId),
            const Variable<String>(_helpOfferSubmitted),
          ],
        )
        .get();
    return [
      for (final row in rows)
        ReconcilableHelpOfferTask(
          beaconId: row.read<String>('beacon_id'),
          helpOffererId: row.read<String>('help_offerer_id'),
          authorId: row.read<String>('author_id'),
          generation: row.read<int>('next_generation'),
        ),
    ];
  }

  /// Inert post-m0203: no open review windows exist, so no review task can
  /// be unbacked. A18 deletes this call path.
  @override
  Future<List<ReconcilableReviewTask>> listUnbackedReviewTasks({
    required String accountId,
  }) =>
      Future.value(const []);

  @override
  Future<int> countUnkeyedLiveObligations({required String accountId}) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT count(*)::int AS unkeyed
FROM public.notification_outbox AS outbox
WHERE outbox.account_id = $1
  AND outbox.requires_action
  AND outbox.settlement_kind IS NULL
  AND outbox.logical_task_key IS NULL
''',
          variables: [Variable<String>(accountId)],
        )
        .get();
    return rows.single.read<int>('unkeyed');
  }
}
