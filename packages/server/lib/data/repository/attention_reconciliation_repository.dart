import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/attention/attention_reconciliation_models.dart';
import 'package:tentura_server/domain/port/attention_reconciliation_port.dart';

import '../database/sql/help_offer_settlement_sql.dart';
import '../database/tentura_db.dart';

/// U12 / D15 — the SQL side of "Reset counters".
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

  static const _helpOfferSubmitted = HelpOfferSettlementSql.helpOfferSubmitted;
  static const _terminalBeaconStatuses =
      HelpOfferSettlementSql.terminalBeaconStatuses;
  static const _terminalCommitmentKinds =
      HelpOfferSettlementSql.terminalCommitmentKinds;
  static const _answeredCommitmentKinds =
      HelpOfferSettlementSql.answeredCommitmentKinds;

  @override
  Future<int> settleObsoleteHelpOfferObligations({
    required String accountId,
  }) => _database.customUpdate(
    HelpOfferSettlementSql.settleStale(accountScope: r'outbox.account_id = $1'),
    variables: [Variable<String>(accountId)],
    updateKind: UpdateKind.update,
  );

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
  AND NOT ${HelpOfferSettlementSql.eventSinceLatestOffer(beaconColumn: 'offer.beacon_id', userColumn: 'offer.user_id', kinds: _terminalCommitmentKinds)}
  AND NOT ${HelpOfferSettlementSql.eventSinceLatestOffer(beaconColumn: 'offer.beacon_id', userColumn: 'offer.user_id', kinds: _answeredCommitmentKinds)}
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
