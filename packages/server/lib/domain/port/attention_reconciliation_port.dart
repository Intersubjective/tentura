import 'package:tentura_server/domain/attention/attention_reconciliation_models.dart';

/// Source-derived obligation repair for **one account** (U12, D15).
///
/// Every statement behind this port is scoped by the account id the caller
/// passes and touches only `notification_outbox` rows that `requires_action`.
/// Nothing here reads or writes `cleared_at`, `seen_at`, `inbox_item` or the
/// attention occurrence log: those record what a person did or saw, and repair
/// has no business there.
abstract class AttentionReconciliationPort {
  /// Settle live `helpOfferSubmitted` obligations whose offer is finished,
  /// using the reason the source gives: `resolved` when the author answered
  /// (accept / decline), `superseded` when the question itself went away
  /// (the helper withdrew, the author removed them, the Request ended).
  Future<int> settleObsoleteHelpOfferObligations({required String accountId});

  /// Settle live `reviewOpened` obligations whose window is no longer open,
  /// with the same outcome rule the window-close path uses: `resolved` when
  /// that reviewer sent their package, `expired` otherwise.
  Future<int> settleObsoleteReviewObligations({required String accountId});

  /// Help-offer tasks that are genuinely still open and carry no live receipt.
  Future<List<ReconcilableHelpOfferTask>> listUnbackedHelpOfferTasks({
    required String accountId,
  });

  /// Review tasks that are genuinely still open and carry no live receipt.
  Future<List<ReconcilableReviewTask>> listUnbackedReviewTasks({
    required String accountId,
  });

  /// Live obligation receipts with no `logical_task_key` (pre-U05c rows).
  /// Reconciliation cannot name their task, so it reports them instead of
  /// guessing. U18 owns the cutover backfill.
  Future<int> countUnkeyedLiveObligations({required String accountId});
}
