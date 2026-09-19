/// U12 / D15 — "Reset counters" is invalidation and repair, not erasure.
///
/// Reconciliation recomputes *derived* obligation state from the source of
/// truth (the help offer, the review window) and nothing else. It may create
/// an obligation that a lost dispatch never wrote, and it may settle one whose
/// source task is finished — always with the reason the source actually gives.
///
/// It may never undo an act of the account's own: a cleared optional receipt,
/// an Inbox stance, a dismissed tombstone, a settled obligation. Those are not
/// derived state, and a repair that "fixed" one would be worse than the wrong
/// count E21 exists to fix.
library;

import 'attention_models.dart';

/// A help-offer task whose author obligation is missing a live receipt.
final class ReconcilableHelpOfferTask {
  const ReconcilableHelpOfferTask({
    required this.beaconId,
    required this.helpOffererId,
    required this.authorId,
    required this.generation,
  });

  final String beaconId;
  final String helpOffererId;
  final String authorId;

  /// Generation the repaired receipt will carry — part of the deterministic
  /// source event key, so a repair of a later generation is a new occurrence
  /// rather than a silent no-op against an earlier one.
  final int generation;
}

/// A review task whose reviewer obligation is missing a live receipt.
final class ReconcilableReviewTask {
  const ReconcilableReviewTask({
    required this.beaconId,
    required this.beaconTitle,
    required this.authorId,
    required this.generation,
  });

  final String beaconId;
  final String beaconTitle;
  final String authorId;
  final int generation;
}

/// The authoritative answer "Reset counters" returns.
///
/// A correct result may still be non-zero — the summary is what the account
/// actually owes after repair, not a promise that the desk is empty.
final class AttentionReconciliationResult {
  const AttentionReconciliationResult({
    required this.createdObligationCount,
    required this.settledObligationCount,
    required this.unrepairableObligationCount,
    required this.summary,
  });

  final int createdObligationCount;
  final int settledObligationCount;

  /// Live obligation receipts reconciliation deliberately did not touch
  /// because it cannot name their task: pre-U05c rows with a NULL
  /// `logical_task_key`. U18 owns those.
  final int unrepairableObligationCount;

  final AttentionSurfaceSummary summary;
}
