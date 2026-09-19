import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/attention/attention_reconciliation_models.dart';
import 'package:tentura_server/domain/port/attention_query_port.dart';
import 'package:tentura_server/domain/port/attention_reconciliation_port.dart';
import 'package:tentura_server/domain/port/attention_system_settlement_port.dart';

import '_use_case_base.dart';
import 'attention_intent_case.dart';
import 'transactional_attention_case.dart';

/// The entry point "Reset counters" calls, as an interface the API layer can
/// depend on (and a test can fake) without building the whole case graph.
// Deliberately a one-member interface: the API layer depends on this instead
// of on the case graph, so a mutation test can fake it.
// ignore: one_member_abstracts
abstract interface class ObligationReconciliationRunner {
  Future<AttentionReconciliationResult> reconcileAccount({
    required String accountId,
  });
}

/// U12 / D15 — reconciliation: repair source-derived obligation state.
///
/// This is the generalisation of `ReviewObligationBackfillCase`, not a second
/// mechanism beside it. [run] is that case's global sweep, unchanged in
/// behaviour and still the deployment-time repair for review windows that
/// closed before settlement shipped. [reconcileAccount] is the per-account
/// repair behind the Settings control, and it covers both obligation kinds
/// U07a found (`helpOfferSubmitted`, `reviewOpened`) in both directions:
/// a live receipt whose task is finished is settled with the source's own
/// reason, and an open task with no live receipt gets one.
///
/// What it must never do is undo an act. It writes only `requires_action`
/// rows; it never touches `cleared_at`, `seen_at`, an Inbox stance, a
/// tombstone, or the occurrence log; and it refuses to re-create an
/// obligation the account settled itself.
@Singleton(order: 2)
final class ObligationReconciliationCase extends UseCaseBase
    implements ObligationReconciliationRunner {
  ObligationReconciliationCase(
    this._systemSettlement,
    this._reconciliation,
    this._query,
    this._attention,
    this._intents, {
    required super.env,
    required super.logger,
  });

  final AttentionSystemSettlementPort _systemSettlement;
  final AttentionReconciliationPort _reconciliation;
  final AttentionQueryPort _query;
  final TransactionalAttentionCase _attention;
  final AttentionIntentCase _intents;

  /// Idempotent sweep for review windows closed before obligation settlement
  /// shipped. Returns total `notification_outbox` rows updated.
  Future<int> run() async {
    final beaconIds = await _systemSettlement
        .listBeaconIdsWithClosedReviewWindows();
    var total = 0;
    for (final beaconId in beaconIds) {
      total += await _systemSettlement.settleReviewObligationsAfterWindowClose(
        beaconId,
      );
    }
    return total;
  }

  @override
  Future<AttentionReconciliationResult> reconcileAccount({
    required String accountId,
  }) async {
    if (accountId.trim().isEmpty || accountId.length > 256) {
      throw ArgumentError.value(
        accountId,
        'accountId',
        'must be an account id',
      );
    }

    final settled =
        await _reconciliation.settleObsoleteHelpOfferObligations(
          accountId: accountId,
        ) +
        await _reconciliation.settleObsoleteReviewObligations(
          accountId: accountId,
        );

    var created = 0;
    for (final task in await _reconciliation.listUnbackedHelpOfferTasks(
      accountId: accountId,
    )) {
      created += await _record(
        accountId: accountId,
        actorUserId: task.helpOffererId,
        intent: await _intents.helpOfferSubmitted(
          beaconId: task.beaconId,
          helpOffererId: task.helpOffererId,
          authorId: task.authorId,
          sourceEventKey:
              'reconcile:help_offer:${task.beaconId}:'
              '${task.helpOffererId}:g${task.generation}',
        ),
      );
    }
    for (final task in await _reconciliation.listUnbackedReviewTasks(
      accountId: accountId,
    )) {
      created += await _record(
        accountId: accountId,
        actorUserId: task.authorId,
        intent: await _intents.reviewOpened(
          beaconId: task.beaconId,
          beaconTitle: task.beaconTitle,
          recipientUserIds: {accountId},
          actorUserId: task.authorId,
          sourceEventKey:
              'reconcile:review_opened:${task.beaconId}:g${task.generation}',
        ),
      );
    }

    return AttentionReconciliationResult(
      createdObligationCount: created,
      settledObligationCount: settled,
      unrepairableObligationCount: await _reconciliation
          .countUnkeyedLiveObligations(accountId: accountId),
      summary: await _query.surfaceSummary(accountId: accountId),
    );
  }

  /// Records [intent] for **the reconciled account only**.
  ///
  /// The intents are the production ones, so they resolve the production
  /// audience — an author *and* any moderator, every reviewer. Repairing one
  /// account's count must not write a receipt for anybody else, so the
  /// recipient list is narrowed here rather than trusted. An account that is
  /// not in the resolved audience is not repaired at all: the obligation would
  /// not have been addressed to them in the first place.
  Future<int> _record({
    required String accountId,
    required String? actorUserId,
    required AttentionDispatchIntent intent,
  }) async {
    final mine = [
      for (final recipient in intent.recipients)
        if (recipient.recipientId == accountId) recipient,
    ];
    if (mine.isEmpty) {
      logger.warning(
        'reconciliation: $accountId is not in the resolved audience of '
        '${intent.eventType.name} on ${intent.beaconId}; not repaired',
      );
      return 0;
    }
    await _attention.runAction(
      actorUserId: actorUserId,
      action: (transaction) =>
          transaction.record(intent.copyWith(recipients: mine)),
    );
    return 1;
  }
}
