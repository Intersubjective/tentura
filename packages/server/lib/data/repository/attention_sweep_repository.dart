import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/attention/attention_clear_models.dart';
import 'package:tentura_server/domain/attention/attention_sweep_models.dart';
import 'package:tentura_server/domain/port/attention_sweep_port.dart';

import '../database/tentura_db.dart';
import 'attention_dismissible_sql.dart';

/// U09b — storage for *Dismiss all*.
///
/// Kept out of `attention_repository.dart` for the same reason U08's clear is:
/// that file is the read projection and U10 rewrites it. Kept out of
/// `attention_clear_repository.dart` too, because the two commands differ in
/// the one place that matters — where membership comes from. U08 is handed a
/// bounded list the client can see; this captures the whole authorized
/// surface, including pages nobody has loaded.
///
/// What it may touch is [AttentionDismissibleSql], composed and never
/// re-derived. Owner decision A is only as strong as the weakest place the
/// question gets asked, and this asks it twice — at capture and again per
/// member at apply time — from the same text.
@Singleton(as: AttentionSweepPort)
class AttentionSweepRepository implements AttentionSweepPort {
  const AttentionSweepRepository(this._database);

  final TenturaDb _database;

  /// The surface this sweep covers. `attention_clear_operation.surface` is
  /// free text (m0178); U08 writes `explicit` / `request_open` / `beacon:<id>`
  /// and this writes the one constant, so an operation's origin is legible
  /// from its header alone.
  static const surface = 'activity';

  /// Every dismissible row of one viewer, both axes, in one statement.
  ///
  /// Exposed so that the exclusion tests can loosen *this* string rather than
  /// a paraphrase of it: an exclusion test that cannot fail is the one defect
  /// that lets the sweep reject somebody's offer of help.
  static const captureSql =
      '''
WITH ${AttentionDismissibleSql.cte}
SELECT
  'receipt' AS kind,
  dismissible.receipt_id AS member_id,
  dismissible.beacon_id AS beacon_id,
  COALESCE(state.outcome_generation, 0) AS outcome_generation,
  COALESCE(state.decision_revision, 0) AS decision_revision
FROM activity_optional_dismissible dismissible
LEFT JOIN public.attention_request_state state
  ON state.account_id = \$1 AND state.beacon_id = dismissible.beacon_id
UNION ALL
SELECT
  'outcome',
  dismissible.beacon_id,
  dismissible.beacon_id,
  dismissible.outcome_generation,
  dismissible.decision_revision
FROM activity_outcome_dismissible dismissible
ORDER BY 1, 2
''';

  @override
  Future<AttentionSweepResult> dismissAll({
    required String accountId,
    required String operationId,
    int batchSize = AttentionSweepLimits.batchSize,
    int? maxBatches,
  }) async {
    final bounded = batchSize.clamp(1, AttentionSweepLimits.maxBatchSize);

    // Phase 1 — the operation header, and membership if this call is the one
    // that created it. `ON CONFLICT DO NOTHING` is the whole idempotency
    // story, inherited from U08: a concurrent twin blocks on the primary key
    // until the winner commits, then finds the membership the winner wrote
    // and never captures its own.
    final captured = await _database.transaction(() async {
      final inserted = await _database.customUpdate(
        r'''
INSERT INTO public.attention_clear_operation
  (id, account_id, surface, status, applied, skipped, failed)
VALUES ($1, $2, $3, 'pending', 0, 0, 0)
ON CONFLICT (id) DO NOTHING
''',
        variables: [
          Variable<String>(operationId),
          Variable<String>(accountId),
          const Variable<String>(surface),
        ],
        updateKind: UpdateKind.insert,
      );
      if (inserted == 0) return false;
      await _capture(
        accountId: accountId,
        operationId: operationId,
        chunkSize: bounded,
      );
      return true;
    });

    if (!captured) {
      // Somebody else's operation id. Say nothing about it — not even whether
      // it exists.
      final owner = await _operationOwner(operationId);
      if (owner != accountId) {
        return AttentionSweepResult(
          operationId: operationId,
          appliedReceiptIds: const [],
          appliedOutcomeBeaconIds: const [],
          skipped: const [],
          failed: const [],
          pending: const [],
          status: AttentionClearStatus.denied,
        );
      }
    }

    return _summarize(operationId);
  }

  /// Membership, captured once and never extended.
  Future<void> _capture({
    required String accountId,
    required String operationId,
    required int chunkSize,
  }) async {
    final rows = await _database
        .customSelect(
          captureSql,
          variables: [Variable<String>(accountId)],
        )
        .get();

    for (var start = 0; start < rows.length; start += chunkSize) {
      final chunk = rows.skip(start).take(chunkSize);
      for (final row in chunk) {
        final isReceipt =
            row.read<String>('kind') ==
            AttentionSweepMemberKind.receipt.wireName;
        final memberId = row.read<String>('member_id');
        await _database.customUpdate(
          r'''
INSERT INTO public.attention_clear_operation_member
  (operation_id, receipt_id, outcome_beacon_id, beacon_id,
   outcome_generation, decision_revision, state)
VALUES ($1, $2, $3, $4, $5, $6, 'pending')
ON CONFLICT (operation_id, receipt_id)
  WHERE receipt_id IS NOT NULL DO NOTHING
''',
          variables: [
            Variable<String>(operationId),
            Variable<String>(isReceipt ? memberId : null),
            Variable<String>(isReceipt ? null : memberId),
            Variable<String>(row.read<String?>('beacon_id')),
            Variable<int>(row.read<int>('outcome_generation')),
            Variable<int>(row.read<int>('decision_revision')),
          ],
          updateKind: UpdateKind.insert,
        );
      }
    }
  }

  Future<String?> _operationOwner(String operationId) async {
    final header = await _database
        .customSelect(
          r'''
SELECT account_id FROM public.attention_clear_operation WHERE id = $1
''',
          variables: [Variable<String>(operationId)],
        )
        .getSingleOrNull();
    return header?.read<String?>('account_id');
  }

  /// The answer, rebuilt from stored membership rather than from what this
  /// call happened to do.
  ///
  /// That is what makes the call that did the work, the call that resumed it
  /// and the concurrent twin that did nothing all report the same thing.
  Future<AttentionSweepResult> _summarize(String operationId) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT receipt_id, outcome_beacon_id, state, skip_reason
  FROM public.attention_clear_operation_member
 WHERE operation_id = $1
 ORDER BY receipt_id NULLS LAST, outcome_beacon_id NULLS LAST
''',
          variables: [Variable<String>(operationId)],
        )
        .get();

    final appliedReceipts = <String>[];
    final appliedOutcomes = <String>[];
    final skipped = <AttentionSweepMember>[];
    final failed = <AttentionSweepMember>[];
    final pending = <AttentionSweepMember>[];

    for (final row in rows) {
      final receiptId = row.read<String?>('receipt_id');
      final kind = receiptId == null
          ? AttentionSweepMemberKind.outcome
          : AttentionSweepMemberKind.receipt;
      final id = receiptId ?? row.read<String>('outcome_beacon_id');
      final reasonText = row.read<String?>('skip_reason');
      final member = AttentionSweepMember(
        kind: kind,
        id: id,
        reason: reasonText == null
            ? null
            : AttentionSweepSkipReason.fromWireName(reasonText),
      );
      switch (row.read<String>('state')) {
        case _stateApplied:
          (kind == AttentionSweepMemberKind.receipt
                  ? appliedReceipts
                  : appliedOutcomes)
              .add(id);
        case _stateSkipped:
          skipped.add(member);
        case _stateFailed:
          failed.add(member);
        case _:
          pending.add(member);
      }
    }

    return AttentionSweepResult(
      operationId: operationId,
      appliedReceiptIds: appliedReceipts,
      appliedOutcomeBeaconIds: appliedOutcomes,
      skipped: skipped,
      failed: failed,
      pending: pending,
      status: _statusOf(
        applied: appliedReceipts.length + appliedOutcomes.length,
        refused: skipped.length + failed.length,
        pending: pending.length,
      ),
    );
  }

  static AttentionClearStatus _statusOf({
    required int applied,
    required int refused,
    required int pending,
  }) {
    if (pending > 0) return AttentionClearStatus.partial;
    if (applied > 0) {
      return refused == 0
          ? AttentionClearStatus.complete
          : AttentionClearStatus.partial;
    }
    if (refused > 0) return AttentionClearStatus.stale;
    return AttentionClearStatus.complete;
  }

  static const _stateApplied = 'applied';
  static const _stateSkipped = 'skipped';
  static const _stateFailed = 'failed';
}
