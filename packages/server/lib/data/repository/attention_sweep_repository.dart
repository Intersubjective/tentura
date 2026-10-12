import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/attention/attention_clear_models.dart';
import 'package:tentura_server/domain/attention/attention_sweep_models.dart';
import 'package:tentura_server/domain/attention/attention_undo_models.dart';
import 'package:tentura_server/domain/port/attention_sweep_port.dart';

import '../database/tentura_db.dart';
import 'attention_dismissible_sql.dart';
import 'constellation_field_repository.dart' show readCustomSelectTimestamptz;

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
  static String get captureSql =>
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

    // Persist the frozen membership before releasing the lane. A retry resumes
    // this snapshot rather than capturing arrivals after the original gesture.
    final snapshot = await _database.transaction(() async {
      final inserted = await _database.customUpdate(
        r'''
INSERT INTO public.attention_clear_operation
        (id, account_id, surface, status, applied, skipped, failed)
        VALUES ($1, $2, $3, 'pending', 0, 0, 0)
        ON CONFLICT (id) DO NOTHING''',
        variables: [
          Variable<String>(operationId),
          Variable<String>(accountId),
          const Variable<String>(surface),
        ],
        updateKind: UpdateKind.insert,
      );
      if (inserted == 0) return null;
      final rows = await _database
          .customSelect(captureSql, variables: [Variable<String>(accountId)])
          .get();
      final members = [for (final row in rows) row.data];
      await _database.customUpdate(
        r'''
UPDATE public.attention_clear_operation
        SET capture_snapshot = $2::jsonb WHERE id = $1''',
        variables: [
          Variable<String>(operationId),
          Variable<String>(members.isEmpty ? null : jsonEncode(members)),
        ],
      );
      return members;
    });
    if (snapshot == null) {
      final header = await _operationHeader(operationId);
      if (header?.owner != accountId) {
        return _emptyResult(operationId, AttentionClearStatus.denied);
      }
      if (header!.status == AttentionClearStatus.expired.name) {
        return _emptyResult(operationId, AttentionClearStatus.expired);
      }
    }
    // A capture another call is still committing is not ours to finish or to
    // report on: until it is whole, nothing is decided and the answer is the
    // non-terminal one.
    if (!await _capture(
      operationId: operationId,
      chunkSize: bounded,
      snapshot: snapshot,
    )) {
      return _emptyResult(operationId, AttentionClearStatus.pending);
    }

    // Phase 2 — decide the still-pending members, a bounded batch at a time.
    //
    // Each batch is its own transaction and takes a row lock on the members it
    // is about to decide, so a concurrent twin blocks, re-reads, and finds
    // those rows no longer pending. Every member is therefore decided exactly
    // once no matter how many callers are in the loop, and both callers leave
    // only when nothing is pending — which is why they can both report the
    // same answer.
    var batches = 0;
    var clearedHere = 0;
    while (maxBatches == null || batches < maxBatches) {
      final batch = await _applyBatch(
        accountId: accountId,
        operationId: operationId,
        batchSize: bounded,
      );
      if (batch.decided == 0) break;
      clearedHere += batch.applied;
      batches++;
    }

    final summary = await _summarize(operationId);

    // The undo window (U09c, D13) opens the first time this operation clears
    // anything and moves forward again whenever a resumed call clears more:
    // a bounded sweep is one gesture, and the window runs from the last thing
    // it actually swept, not from the call that started it. `GREATEST` keeps
    // it monotonic, and a call that cleared nothing — a replay, a concurrent
    // twin, a resume that found everything already decided — leaves it exactly
    // where it was. Otherwise replaying an id would buy unlimited undo time.
    await _database.customUpdate(
      r'''
UPDATE public.attention_clear_operation
   SET status = $2, applied = $3, skipped = $4, failed = $5,
       undo_deadline = CASE
         WHEN $6 THEN GREATEST(
           COALESCE(undo_deadline, now()),
           now() + make_interval(secs => $7)
         )
         ELSE undo_deadline
       END
 WHERE id = $1
''',
      variables: [
        Variable<String>(operationId),
        Variable<String>(summary.status.name),
        Variable<int>(summary.appliedCount),
        Variable<int>(summary.skipped.length),
        Variable<int>(summary.failed.length),
        Variable<bool>(clearedHere > 0),
        Variable<double>(
          AttentionUndoLimits.window.inMilliseconds /
              Duration.millisecondsPerSecond,
        ),
      ],
      updateKind: UpdateKind.update,
    );

    final deadline = await _undoDeadline(operationId);
    return AttentionSweepResult(
      operationId: summary.operationId,
      appliedReceiptIds: summary.appliedReceiptIds,
      appliedOutcomeBeaconIds: summary.appliedOutcomeBeaconIds,
      skipped: summary.skipped,
      failed: summary.failed,
      pending: summary.pending,
      status: summary.status,
      undoDeadline: deadline,
      undoToken: deadline == null
          ? null
          : AttentionUndoToken(
              accountId: accountId,
              operationId: operationId,
            ).encode(),
    );
  }

  Future<DateTime?> _undoDeadline(String operationId) async {
    final row = await _database
        .customSelect(
          r'''
SELECT undo_deadline FROM public.attention_clear_operation WHERE id = $1
''',
          variables: [Variable<String>(operationId)],
        )
        .getSingleOrNull();
    // Drift reads a customSelect `timestamptz` as unix seconds and
    // `int.parse`s the driver's `DateTime.toString()`; this helper is the
    // repo's existing way round that.
    return readCustomSelectTimestamptz(row?.data['undo_deadline']);
  }

  /// One batch: re-ask the dismissible question per member, then write.
  ///
  /// Re-asking is the whole point of doing this here rather than trusting the
  /// capture. A member that became ineligible in between — the forward was
  /// restored, the viewer took responsibility, another gesture got there
  /// first — is *skipped and reported*, never cleared, and never dropped
  /// silently. Returns how many members this call decided, and how many of
  /// those it actually cleared — the second number is what opens and moves the
  /// undo window, because a batch that only skipped did no work to undo.
  Future<({int decided, int applied})> _applyBatch({
    required String accountId,
    required String operationId,
    required int batchSize,
  }) => _database.transaction(() async {
    final pending = await _database
        .customSelect(
          r'''
SELECT receipt_id, outcome_beacon_id, outcome_generation, decision_revision
  FROM public.attention_clear_operation_member
 WHERE operation_id = $1 AND state = 'pending'
 ORDER BY receipt_id NULLS LAST, outcome_beacon_id NULLS LAST
 LIMIT $2
 FOR UPDATE
''',
          variables: [
            Variable<String>(operationId),
            Variable<int>(batchSize),
          ],
        )
        .get();
    if (pending.isEmpty) return (decided: 0, applied: 0);

    final receiptIds = <String>[];
    final outcomeIds = <String>[];
    final capturedIdentity = <String, (int, int)>{};
    for (final row in pending) {
      final receiptId = row.read<String?>('receipt_id');
      final id = receiptId ?? row.read<String>('outcome_beacon_id');
      (receiptId == null ? outcomeIds : receiptIds).add(id);
      capturedIdentity[id] = (
        row.read<int>('outcome_generation'),
        row.read<int?>('decision_revision') ?? 0,
      );
    }

    final decisions = <String, (String, AttentionSweepSkipReason?)>{};

    // 1. The same predicate as the capture, asked again — per member, now.
    final eligible = await _eligibleNow(
      accountId: accountId,
      receiptIds: receiptIds,
      outcomeIds: outcomeIds,
    );

    // 2. Outcomes whose Request was decided underneath the sweep are not the
    // row the person saw. `tombstone_dismissed_at` bumps neither counter
    // (U09a), so an unmoved outcome always matches its own snapshot.
    final applicableOutcomes = <String>[];
    for (final id in outcomeIds) {
      final live = eligible[id];
      if (live == null) continue;
      if (live == capturedIdentity[id]) {
        applicableOutcomes.add(id);
      } else {
        decisions[id] = (
          _stateSkipped,
          AttentionSweepSkipReason.decisionChanged,
        );
      }
    }

    // 3. Receipts: one guarded UPDATE, then read back which rows this
    // operation actually cleared. "Applied" means cleared, and nothing that
    // was not cleared is allowed to be reported as applied.
    final applicableReceipts = [
      for (final id in receiptIds)
        if (eligible.containsKey(id)) id,
    ];
    if (applicableReceipts.isNotEmpty) {
      final placeholders = _placeholders(applicableReceipts.length, from: 3);
      final variables = [
        Variable<String>(accountId),
        Variable<String>(operationId),
        for (final id in applicableReceipts) Variable<String>(id),
      ];
      // The guard clauses are the shared predicate, not a paraphrase of it:
      // the apply re-check decides, at the last moment before the write, the
      // same question capture asked. Composed rather than spelled out so the
      // structural guard in the axis suite can see there is one definition.
      await _database.customUpdate(
        '''
UPDATE public.notification_outbox AS receipt
   SET cleared_at = now(),
       clear_reason = 'sweep',
       cleared_by_operation_id = \$2
 WHERE receipt.account_id = \$1
   AND ${AttentionDismissibleSql.activeOptional('receipt')}
   AND receipt.id IN ($placeholders)
''',
        variables: variables,
        updateKind: UpdateKind.update,
      );
      final clearedRows = await _database.customSelect(
        '''
SELECT id FROM public.notification_outbox
 WHERE account_id = \$1
   AND cleared_by_operation_id = \$2
   AND id IN ($placeholders)
''',
        variables: variables,
      ).get();
      final cleared = {for (final row in clearedRows) row.read<String>('id')};
      for (final id in applicableReceipts) {
        decisions[id] = cleared.contains(id)
            ? (_stateApplied, null)
            : (_stateSkipped, AttentionSweepSkipReason.alreadyCleared);
      }
    }

    // One guarded bulk update per outcome axis; a savepoint preserves the
    // existing database-refusal result without aborting receipt decisions.
    if (applicableOutcomes.isNotEmpty) {
      decisions.addAll(
        await _dismissOutcomes(
          accountId: accountId,
          beaconIds: applicableOutcomes,
        ),
      );
    }

    // 5. Everything the predicate refused, with the reason it refused it.
    final refused = [
      for (final id in [...receiptIds, ...outcomeIds])
        if (!decisions.containsKey(id)) id,
    ];
    if (refused.isNotEmpty) {
      final reasons = await _refusalReasons(
        accountId: accountId,
        receiptIds: [
          for (final id in receiptIds)
            if (refused.contains(id)) id,
        ],
        outcomeIds: [
          for (final id in outcomeIds)
            if (refused.contains(id)) id,
        ],
      );
      for (final id in refused) {
        decisions[id] = (
          _stateSkipped,
          reasons[id] ?? AttentionSweepSkipReason.notAuthorized,
        );
      }
    }

    await _database.customUpdate(
      r'''
UPDATE public.attention_clear_operation_member AS member
      SET state = decision.state, skip_reason = decision.skip_reason
      FROM jsonb_to_recordset($2::jsonb)
        AS decision(id text, state text, skip_reason text)
      WHERE member.operation_id = $1
        AND (member.receipt_id = decision.id OR member.outcome_beacon_id = decision.id)''',
      variables: [
        Variable<String>(operationId),
        Variable<String>(
          jsonEncode([
            for (final entry in decisions.entries)
              {
                'id': entry.key,
                'state': entry.value.$1,
                'skip_reason': entry.value.$2?.wireName,
              },
          ]),
        ),
      ],
      updateKind: UpdateKind.update,
    );
    return (
      decided: decisions.length,
      applied: decisions.values
          .where((decision) => decision.$1 == _stateApplied)
          .length,
    );
  });

  /// The dismissible question, asked again for exactly these members.
  ///
  /// Returns the live `(outcome_generation, decision_revision)` of every
  /// member still eligible; absence means "not dismissible now", whatever the
  /// reason, and the reason is asked for separately.
  Future<Map<String, (int, int)>> _eligibleNow({
    required String accountId,
    required List<String> receiptIds,
    required List<String> outcomeIds,
  }) async {
    if (receiptIds.isEmpty && outcomeIds.isEmpty) return const {};
    final variables = [
      Variable<String>(accountId),
      for (final id in receiptIds) Variable<String>(id),
      for (final id in outcomeIds) Variable<String>(id),
    ];
    final branches = <String>[
      if (receiptIds.isNotEmpty)
        '''
SELECT receipt_id AS member_id, 0 AS outcome_generation, 0 AS decision_revision
  FROM activity_optional_dismissible
 WHERE receipt_id IN (${_placeholders(receiptIds.length, from: 2)})''',
      if (outcomeIds.isNotEmpty)
        '''
SELECT beacon_id AS member_id, outcome_generation, decision_revision
  FROM activity_outcome_dismissible
 WHERE beacon_id IN (
   ${_placeholders(outcomeIds.length, from: 2 + receiptIds.length)})''',
    ];
    final rows = await _database
        .customSelect(
          'WITH ${AttentionDismissibleSql.cte}\n${branches.join('\nUNION ALL\n')}',
          variables: variables,
        )
        .get();
    return {
      for (final row in rows)
        row.read<String>('member_id'): (
          row.read<int>('outcome_generation'),
          row.read<int>('decision_revision'),
        ),
    };
  }

  /// Why the predicate refused a member.
  ///
  /// A skip without a reason is not a report: "the forward is awaiting your
  /// answer again" and "you may no longer read this" are different facts
  /// about the world, and only one of them is a bug if it happens often.
  /// Absence from both lookups means the row is gone or was never the
  /// caller's, which is deliberately one answer — the sweep does not disclose
  /// which.
  Future<Map<String, AttentionSweepSkipReason>> _refusalReasons({
    required String accountId,
    required List<String> receiptIds,
    required List<String> outcomeIds,
  }) async {
    final reasons = <String, AttentionSweepSkipReason>{};
    if (receiptIds.isNotEmpty) {
      final rows = await _database
          .customSelect(
            '''
WITH ${AttentionDismissibleSql.prelude}
SELECT receipt.id AS member_id,
       CASE
         WHEN receipt.cleared_at IS NOT NULL THEN 'already_cleared'
         WHEN receipt.requires_action THEN 'obligation'
         WHEN receipt.beacon_id IS NOT NULL
          AND receipt.beacon_id IN (SELECT scope.beacon_id FROM scope)
           THEN 'responsibility_gained'
         ELSE 'not_authorized'
       END AS reason
  FROM public.notification_outbox receipt
 WHERE receipt.account_id = \$1
   AND receipt.id IN (${_placeholders(receiptIds.length, from: 2)})
''',
            variables: [
              Variable<String>(accountId),
              for (final id in receiptIds) Variable<String>(id),
            ],
          )
          .get();
      for (final row in rows) {
        reasons[row.read<String>('member_id')] =
            AttentionSweepSkipReason.fromWireName(row.read<String>('reason'));
      }
    }
    if (outcomeIds.isNotEmpty) {
      final rows = await _database
          .customSelect(
            '''
WITH ${AttentionDismissibleSql.prelude}
SELECT ii.beacon_id AS member_id,
       CASE
         WHEN ii.tombstone_dismissed_at IS NOT NULL THEN 'already_cleared'
         WHEN ii.beacon_id IN (SELECT eligible_pinned.beacon_id
                                 FROM eligible_pinned)
           THEN 'awaiting_decision'
         ELSE 'not_authorized'
       END AS reason
  FROM public.inbox_item ii
 WHERE ii.user_id = \$1
   AND ii.beacon_id IN (${_placeholders(outcomeIds.length, from: 2)})
''',
            variables: [
              Variable<String>(accountId),
              for (final id in outcomeIds) Variable<String>(id),
            ],
          )
          .get();
      for (final row in rows) {
        reasons[row.read<String>('member_id')] =
            AttentionSweepSkipReason.fromWireName(row.read<String>('reason'));
      }
    }
    return reasons;
  }

  Future<Map<String, (String, AttentionSweepSkipReason?)>> _dismissOutcomes({
    required String accountId,
    required List<String> beaconIds,
  }) async {
    await _database.customStatement('SAVEPOINT attention_sweep_members');
    try {
      final rows = await _database
          .customSelect(
            r'''
UPDATE public.inbox_item SET tombstone_dismissed_at = now()
        WHERE user_id = $1
          AND beacon_id = ANY(ARRAY(SELECT jsonb_array_elements_text($2::jsonb)))
          AND tombstone_dismissed_at IS NULL RETURNING beacon_id''',
            variables: [
              Variable<String>(accountId),
              Variable<String>(jsonEncode(beaconIds)),
            ],
          )
          .get();
      await _database.customStatement(
        'RELEASE SAVEPOINT attention_sweep_members',
      );
      final applied = {for (final row in rows) row.read<String>('beacon_id')};
      return {
        for (final id in beaconIds)
          id: applied.contains(id)
              ? (_stateApplied, null)
              : (_stateSkipped, AttentionSweepSkipReason.alreadyCleared),
      };
    } on Object {
      await _database.customStatement(
        'ROLLBACK TO SAVEPOINT attention_sweep_members',
      );
      await _database.customStatement(
        'RELEASE SAVEPOINT attention_sweep_members',
      );
      return {
        for (final id in beaconIds)
          id: (_stateFailed, AttentionSweepSkipReason.refused),
      };
    }
  }

  // ---------------------------------------------------------------- U09c ---
  //
  // Undo. Every guard below is a separate named constant so a test can delete
  // exactly that clause from the exact text this repository runs and watch the
  // row come back. A refusal test that cannot fail is the defect that lets
  // undo resurrect somebody else's decision.

  /// "This operation is the one that cleared it." Without it, undo reverses
  /// another device's sweep or a later explicit ×.
  static const undoReceiptOperationGuard =
      r'AND receipt.cleared_by_operation_id = $2';

  /// "Nothing decided anything about this Request since the sweep." U09a's two
  /// counters, compared against the snapshot taken at capture. Without it,
  /// undo puts a dismissed receipt back on top of a decision the person made
  /// afterwards — later intent loses, which is the one thing D13 forbids.
  static const undoReceiptCountersGuard = r'''
   AND (
     SELECT COALESCE(max(ars.decision_revision), 0)
       FROM public.attention_request_state ars
      WHERE ars.account_id = $1 AND ars.beacon_id = receipt.beacon_id
   ) = COALESCE(member.decision_revision, 0)
   AND (
     SELECT COALESCE(max(ars.outcome_generation), 0)
       FROM public.attention_request_state ars
      WHERE ars.account_id = $1 AND ars.beacon_id = receipt.beacon_id
   ) = member.outcome_generation''';

  /// "The sweep actually applied this member." Shared by both axes. Without
  /// it, undo restores rows a bounded sweep never got to, which is undo
  /// silently finishing an operation it was asked to reverse.
  static const undoAppliedStateGuard = "AND member.state = 'applied'";

  /// The receipt half of undo, guards and all.
  ///
  /// `$1` account, `$2` operation, `$3` receipt id. It returns the id only
  /// when it really restored the row, so "restored" is read back from the
  /// database rather than assumed — the same rule the sweep applies to
  /// "applied".
  ///
  /// There is deliberately **no** obligation guard here. A cleared receipt
  /// cannot be an obligation: `notification_outbox__clear_optional_only_chk`
  /// makes that state unrepresentable, so a member still carrying this
  /// operation's clear is optional by construction. A guard nobody can make
  /// fail is not protection, it is decoration.
  static const undoReceiptSql =
      '''
UPDATE public.notification_outbox AS receipt
   SET cleared_at = NULL,
       clear_reason = NULL,
       cleared_by_operation_id = NULL
  FROM public.attention_clear_operation_member AS member
 WHERE member.operation_id = \$2
   AND member.receipt_id = receipt.id
   AND receipt.account_id = \$1
   AND receipt.id = \$3
   $undoAppliedStateGuard
   $undoReceiptOperationGuard
   AND receipt.id IN (
     SELECT receipt_id FROM public.visible_attention_receipts(\$1)
   )
$undoReceiptCountersGuard
RETURNING receipt.id
''';

  /// The outcome half's counters guard — the same rule as the receipt half,
  /// written against `inbox_item`. A Restore or a re-pin moves
  /// `decision_revision`, a new forward generation or a terminal state moves
  /// `outcome_generation`, and either one means the row in front of the
  /// person is not the row the sweep hid.
  static const undoOutcomeCountersGuard = r'''
   AND (
     SELECT COALESCE(max(ars.decision_revision), 0)
       FROM public.attention_request_state ars
      WHERE ars.account_id = $1 AND ars.beacon_id = ii.beacon_id
   ) = COALESCE(member.decision_revision, 0)
   AND (
     SELECT COALESCE(max(ars.outcome_generation), 0)
       FROM public.attention_request_state ars
      WHERE ars.account_id = $1 AND ars.beacon_id = ii.beacon_id
   ) = member.outcome_generation''';

  /// Authorization, re-asked at undo time in the same words
  /// `AttentionDismissibleSql.dismissibleOutcomes` asks it. Without it, undo
  /// puts back a row the viewer may no longer read.
  static const undoOutcomeReadabilityGuard = r'''
   AND (
     public.beacon_can_read_content(ii.beacon_id, $1)
     OR (
       ii.status IN (3, 4)
       AND public.beacon_can_read_tombstone(ii.beacon_id, $1)
     )
   )''';

  /// The outcome half of undo. `$1` account, `$2` operation, `$3` Request id.
  static const undoOutcomeSql =
      '''
UPDATE public.inbox_item AS ii
   SET tombstone_dismissed_at = NULL
  FROM public.attention_clear_operation_member AS member
 WHERE member.operation_id = \$2
   AND member.outcome_beacon_id = ii.beacon_id
   AND ii.user_id = \$1
   AND ii.beacon_id = \$3
   $undoAppliedStateGuard
   AND ii.tombstone_dismissed_at IS NOT NULL
$undoOutcomeCountersGuard
$undoOutcomeReadabilityGuard
RETURNING ii.beacon_id
''';

  @override
  Future<AttentionUndoResult> undo({
    required String accountId,
    required String operationId,
    required String undoToken,
  }) async {
    final members = await _database
        .customSelect(
          r'''
SELECT receipt_id, outcome_beacon_id, state
      FROM public.attention_clear_operation_member WHERE operation_id = $1
      ORDER BY receipt_id NULLS LAST, outcome_beacon_id NULLS LAST''',
          variables: [Variable<String>(operationId)],
        )
        .get();
    final receipts = <String>[];
    final outcomes = <String>[];
    final skipped = <AttentionUndoMember>[];
    final failed = <AttentionUndoMember>[];
    AttentionUndoRefusal? refusal;
    for (
      var start = 0;
      start < members.length || start == 0;
      start += AttentionSweepLimits.maxBatchSize
    ) {
      final result = await _undoBatch(
        accountId: accountId,
        operationId: operationId,
        members: members
            .skip(start)
            .take(AttentionSweepLimits.maxBatchSize)
            .toList(),
        // The window is judged once, by the first chunk; later chunks finish
        // what that decision admitted.
        checkDeadline: start == 0,
      );
      if (result.refusal != null) {
        if (receipts.isEmpty && outcomes.isEmpty) return result;
        refusal = result.refusal;
        for (final row in members.skip(start)) {
          final receiptId = row.read<String?>('receipt_id');
          failed.add(
            AttentionUndoMember(
              kind: receiptId == null ? 'outcome' : 'receipt',
              id: receiptId ?? row.read<String>('outcome_beacon_id'),
              reason: AttentionUndoSkipReason.refused,
            ),
          );
        }
        break;
      }
      receipts.addAll(result.restoredReceiptIds);
      outcomes.addAll(result.restoredOutcomeBeaconIds);
      skipped.addAll(result.skipped);
      failed.addAll(result.failed);
    }
    final restored = receipts.length + outcomes.length;
    final refused = skipped.length + failed.length;
    return AttentionUndoResult(
      operationId: operationId,
      restoredReceiptIds: receipts,
      restoredOutcomeBeaconIds: outcomes,
      skipped: skipped,
      failed: failed,
      refusal: refusal,
      status: restored > 0
          ? (refused == 0
                ? AttentionUndoStatus.complete
                : AttentionUndoStatus.partial)
          : (refused > 0
                ? AttentionUndoStatus.stale
                : AttentionUndoStatus.complete),
    );
  }

  Future<AttentionUndoResult> _undoBatch({
    required String accountId,
    required String operationId,
    required List<QueryRow> members,
    required bool checkDeadline,
  }) => _database.transaction(() async {
    // The window is a server column compared against the server's clock, and
    // it is read inside the transaction that would restore. Only the first
    // chunk of an undo asks (`checkDeadline`): an undo that began inside the
    // window finishes every chunk, so a deadline passing mid-undo never
    // leaves it half-applied.
    final header = await _database
        .customSelect(
          r'''
SELECT account_id,
       undo_deadline IS NULL AS never_applied,
       undo_deadline < now() AS expired
  FROM public.attention_clear_operation
 WHERE id = $1
 FOR UPDATE
''',
          variables: [Variable<String>(operationId)],
        )
        .getSingleOrNull();

    AttentionUndoResult refused(AttentionUndoRefusal refusal) =>
        AttentionUndoResult.refused(
          operationId: operationId,
          refusal: refusal,
        );

    // A missing operation and somebody else's operation answer identically:
    // undo must not be a way to discover which ids exist.
    if (header == null || header.read<String?>('account_id') != accountId) {
      return refused(AttentionUndoRefusal.notFound);
    }
    if (header.read<bool>('never_applied')) {
      return refused(AttentionUndoRefusal.neverApplied);
    }
    if (checkDeadline && header.read<bool>('expired')) {
      return refused(AttentionUndoRefusal.expired);
    }

    final restoredReceipts = <String>[];
    final restoredOutcomes = <String>[];
    final skipped = <AttentionUndoMember>[];
    final failed = <AttentionUndoMember>[];
    final unrestoredReceipts = <String>[];
    final unrestoredOutcomes = <String>[];

    final receiptIds = [
      for (final row in members)
        if (row.read<String>('state') == _stateApplied &&
            row.read<String?>('receipt_id') != null)
          row.read<String>('receipt_id'),
    ];
    final outcomeIds = [
      for (final row in members)
        if (row.read<String>('state') == _stateApplied &&
            row.read<String?>('receipt_id') == null)
          row.read<String>('outcome_beacon_id'),
    ];
    final restoredMembers = <String, _RestoreOutcome>{};
    if (receiptIds.isNotEmpty) {
      restoredMembers.addAll(
        await _restoreMembers(
          accountId: accountId,
          operationId: operationId,
          memberIds: receiptIds,
          isReceipt: true,
        ),
      );
    }
    if (outcomeIds.isNotEmpty) {
      restoredMembers.addAll(
        await _restoreMembers(
          accountId: accountId,
          operationId: operationId,
          memberIds: outcomeIds,
          isReceipt: false,
        ),
      );
    }
    for (final row in members) {
      final receiptId = row.read<String?>('receipt_id');
      final isReceipt = receiptId != null;
      final id = receiptId ?? row.read<String>('outcome_beacon_id');
      final kind = isReceipt ? 'receipt' : 'outcome';
      final state = row.read<String>('state');

      // Never applied, never restored. A bounded sweep's pending members stay
      // pending: undo reverses what happened, it does not finish what did not.
      if (state != _stateApplied) {
        skipped.add(
          AttentionUndoMember(
            kind: kind,
            id: id,
            reason: state == _stateUndone
                ? AttentionUndoSkipReason.alreadyRestored
                : AttentionUndoSkipReason.notApplied,
          ),
        );
        continue;
      }

      final outcome = restoredMembers[id]!;
      switch (outcome) {
        case _RestoreOutcome.restored:
          (isReceipt ? restoredReceipts : restoredOutcomes).add(id);
        case _RestoreOutcome.refusedByGuard:
          (isReceipt ? unrestoredReceipts : unrestoredOutcomes).add(id);
        case _RestoreOutcome.databaseRefused:
          failed.add(
            AttentionUndoMember(
              kind: kind,
              id: id,
              reason: AttentionUndoSkipReason.refused,
            ),
          );
      }
    }

    // A skip without a reason is not a report, so the guards that refused are
    // asked, once, which one it was.
    if (unrestoredReceipts.isNotEmpty || unrestoredOutcomes.isNotEmpty) {
      final reasons = await _undoRefusalReasons(
        accountId: accountId,
        operationId: operationId,
        receiptIds: unrestoredReceipts,
        outcomeIds: unrestoredOutcomes,
      );
      for (final id in unrestoredReceipts) {
        skipped.add(
          AttentionUndoMember(
            kind: 'receipt',
            id: id,
            reason: reasons[id] ?? AttentionUndoSkipReason.notAuthorized,
          ),
        );
      }
      for (final id in unrestoredOutcomes) {
        skipped.add(
          AttentionUndoMember(
            kind: 'outcome',
            id: id,
            reason: reasons[id] ?? AttentionUndoSkipReason.notAuthorized,
          ),
        );
      }
    }

    if (restoredReceipts.isNotEmpty || restoredOutcomes.isNotEmpty) {
      await _database.customUpdate(
        r'''
UPDATE public.attention_clear_operation_member
        SET state = 'undone'
        WHERE operation_id = $1 AND (receipt_id = ANY(
          ARRAY(SELECT jsonb_array_elements_text($2::jsonb)))
          OR outcome_beacon_id = ANY(ARRAY(SELECT jsonb_array_elements_text($2::jsonb))))''',
        variables: [
          Variable<String>(operationId),
          Variable<String>(
            jsonEncode([...restoredReceipts, ...restoredOutcomes]),
          ),
        ],
        updateKind: UpdateKind.update,
      );
    }

    // The header records that the operation was undone only when nothing it
    // applied is still applied. The sweep's counters are left alone on
    // purpose: they say what the sweep did, which undo does not change.
    await _database.customUpdate(
      r'''
UPDATE public.attention_clear_operation
   SET status = CASE
         WHEN NOT EXISTS (
           SELECT 1 FROM public.attention_clear_operation_member member
            WHERE member.operation_id = $1 AND member.state = 'applied'
         ) AND EXISTS (
           SELECT 1 FROM public.attention_clear_operation_member member
            WHERE member.operation_id = $1 AND member.state = 'undone'
         ) THEN 'undone'
         ELSE status
       END
 WHERE id = $1
''',
      variables: [Variable<String>(operationId)],
      updateKind: UpdateKind.update,
    );

    final restored = restoredReceipts.length + restoredOutcomes.length;
    final refusedCount = skipped.length + failed.length;
    return AttentionUndoResult(
      operationId: operationId,
      restoredReceiptIds: restoredReceipts,
      restoredOutcomeBeaconIds: restoredOutcomes,
      skipped: skipped,
      failed: failed,
      status: restored > 0
          ? (refusedCount == 0
                ? AttentionUndoStatus.complete
                : AttentionUndoStatus.partial)
          : (refusedCount > 0
                ? AttentionUndoStatus.stale
                : AttentionUndoStatus.complete),
    );
  });

  /// Restore one bounded axis, retaining every authorization/snapshot guard.
  Future<Map<String, _RestoreOutcome>> _restoreMembers({
    required String accountId,
    required String operationId,
    required List<String> memberIds,
    required bool isReceipt,
  }) async {
    await _database.customStatement('SAVEPOINT attention_undo_members');
    try {
      final sql = isReceipt
          ? undoReceiptSql.replaceFirst(
              r'receipt.id = $3',
              r'receipt.id = ANY(ARRAY(SELECT jsonb_array_elements_text($3::jsonb)))',
            )
          : undoOutcomeSql
                .replaceFirst(
                  r'ii.beacon_id = $3',
                  r'ii.beacon_id = ANY(ARRAY(SELECT jsonb_array_elements_text($3::jsonb)))',
                )
                .replaceFirst(
                  'RETURNING ii.beacon_id',
                  'RETURNING ii.beacon_id AS id',
                );
      final rows = await _database
          .customSelect(
            sql,
            variables: [
              Variable<String>(accountId),
              Variable<String>(operationId),
              Variable<String>(jsonEncode(memberIds)),
            ],
          )
          .get();
      await _database.customStatement(
        'RELEASE SAVEPOINT attention_undo_members',
      );
      final restored = {for (final row in rows) row.read<String>('id')};
      return {
        for (final id in memberIds)
          id: restored.contains(id)
              ? _RestoreOutcome.restored
              : _RestoreOutcome.refusedByGuard,
      };
    } on Object {
      await _database.customStatement(
        'ROLLBACK TO SAVEPOINT attention_undo_members',
      );
      await _database.customStatement(
        'RELEASE SAVEPOINT attention_undo_members',
      );
      return {for (final id in memberIds) id: _RestoreOutcome.databaseRefused};
    }
  }

  Future<Map<String, AttentionUndoSkipReason>> _undoRefusalReasons({
    required String accountId,
    required String operationId,
    required List<String> receiptIds,
    required List<String> outcomeIds,
  }) async {
    final reasons = <String, AttentionUndoSkipReason>{};
    if (receiptIds.isNotEmpty) {
      final rows = await _database
          .customSelect(
            '''
SELECT receipt.id AS member_id,
       CASE
         WHEN receipt.cleared_by_operation_id IS NULL THEN 'already_restored'
         WHEN receipt.cleared_by_operation_id <> \$2
           THEN 'cleared_by_another_operation'
         WHEN receipt.id NOT IN (
           SELECT receipt_id FROM public.visible_attention_receipts(\$1)
         ) THEN 'not_authorized'
         ELSE 'decision_changed'
       END AS reason
  FROM public.notification_outbox receipt
 WHERE receipt.account_id = \$1
   AND receipt.id IN (${_placeholders(receiptIds.length, from: 3)})
''',
            variables: [
              Variable<String>(accountId),
              Variable<String>(operationId),
              for (final id in receiptIds) Variable<String>(id),
            ],
          )
          .get();
      for (final row in rows) {
        reasons[row.read<String>('member_id')] =
            AttentionUndoSkipReason.fromWireName(row.read<String>('reason'));
      }
    }
    if (outcomeIds.isNotEmpty) {
      final rows = await _database
          .customSelect(
            '''
SELECT ii.beacon_id AS member_id,
       CASE
         WHEN ii.tombstone_dismissed_at IS NULL THEN 'already_restored'
         WHEN NOT (
           public.beacon_can_read_content(ii.beacon_id, \$1)
           OR (
             ii.status IN (3, 4)
             AND public.beacon_can_read_tombstone(ii.beacon_id, \$1)
           )
         ) THEN 'not_authorized'
         ELSE 'decision_changed'
       END AS reason
  FROM public.inbox_item ii
 WHERE ii.user_id = \$1
   AND ii.beacon_id IN (${_placeholders(outcomeIds.length, from: 2)})
''',
            variables: [
              Variable<String>(accountId),
              for (final id in outcomeIds) Variable<String>(id),
            ],
          )
          .get();
      for (final row in rows) {
        reasons[row.read<String>('member_id')] =
            AttentionUndoSkipReason.fromWireName(row.read<String>('reason'));
      }
    }
    return reasons;
  }

  static String _placeholders(int count, {required int from}) =>
      List.generate(count, (index) => '\$${index + from}').join(',');

  /// Membership, captured once and never extended.
  ///
  /// Returns false when the capture is still open after another call took the
  /// cursor from this one and stopped advancing for [_captureStallWait]. Capture
  /// commits in bounded chunks, so between two chunks nobody holds a lock on
  /// the operation: a lost cursor compare-and-set only proves somebody else is
  /// capturing, never that the capture is over.
  Future<bool> _capture({
    required String operationId,
    required int chunkSize,
    List<Map<String, dynamic>>? snapshot,
  }) async {
    var cursor = 0;
    var members = snapshot;
    if (members == null) {
      final header = await _database
          .customSelect(
            r'''
SELECT capture_snapshot::text AS capture_snapshot, capture_cursor
        FROM public.attention_clear_operation WHERE id = $1''',
            variables: [Variable<String>(operationId)],
          )
          .getSingleOrNull();
      final raw = header?.read<String?>('capture_snapshot');
      if (raw == null) return true;
      members = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      cursor = header!.read<int>('capture_cursor');
    }
    for (var start = cursor; start < members.length; start += chunkSize) {
      final chunk = members.skip(start).take(chunkSize).toList();
      final next = start + chunk.length;
      final claimedChunk = await _database.transaction(() async {
        // The cursor update locks the header and fences concurrent resumptions.
        // It commits with the members, including clearing the final snapshot.
        // `captured_at` moves with it: it is when the capture was last touched.
        final claimed = await _database.customUpdate(
          r'''
UPDATE public.attention_clear_operation
          SET capture_cursor = $2,
              captured_at = now(),
              capture_snapshot = CASE WHEN $4 THEN NULL ELSE capture_snapshot END
          WHERE id = $1 AND capture_cursor = $3''',
          variables: [
            Variable<String>(operationId),
            Variable<int>(next),
            Variable<int>(start),
            Variable<bool>(next == members!.length),
          ],
        );
        if (claimed == 0) return false;
        await _database.customUpdate(
          r'''
INSERT INTO public.attention_clear_operation_member
          (operation_id, receipt_id, outcome_beacon_id, beacon_id,
           outcome_generation, decision_revision, state)
          SELECT $1,
            CASE WHEN m.kind = 'receipt' THEN m.member_id END,
            CASE WHEN m.kind = 'outcome' THEN m.member_id END,
            m.beacon_id, m.outcome_generation, m.decision_revision, 'pending'
          FROM jsonb_to_recordset($2::jsonb) AS m(kind text, member_id text,
            beacon_id text, outcome_generation integer, decision_revision integer)
          ON CONFLICT DO NOTHING''',
          variables: [
            Variable<String>(operationId),
            Variable<String>(jsonEncode(chunk)),
          ],
          updateKind: UpdateKind.insert,
        );
        return true;
      });
      if (!claimedChunk) return _awaitCapture(operationId);
    }
    return true;
  }

  static const _captureStallWait = Duration(seconds: 10);
  static const _capturePoll = Duration(milliseconds: 50);

  /// Waits for another call's capture of [operationId] to finish.
  ///
  /// How long a capture takes depends on load, so only a capture that stops
  /// committing chunks for [_captureStallWait] is given up on; one whose
  /// cursor keeps moving is waited for however long it takes.
  Future<bool> _awaitCapture(String operationId) async {
    int? lastCursor;
    var stallDeadline = DateTime.now().add(_captureStallWait);
    while (true) {
      final row = await _database
          .customSelect(
            r'''
SELECT capture_snapshot IS NULL AS done, capture_cursor
  FROM public.attention_clear_operation WHERE id = $1''',
            variables: [Variable<String>(operationId)],
          )
          .getSingleOrNull();
      if (row?.read<bool>('done') ?? true) return true;
      final cursor = row!.read<int>('capture_cursor');
      if (cursor != lastCursor) {
        lastCursor = cursor;
        stallDeadline = DateTime.now().add(_captureStallWait);
      } else if (DateTime.now().isAfter(stallDeadline)) {
        return false;
      }
      await Future<void>.delayed(_capturePoll);
    }
  }

  /// Settles clears whose capture was started and then abandoned: still
  /// `pending` with the frozen snapshot stored, and not touched for
  /// [staleAfter]. Those older than [expireAfter] are expired — every member
  /// decided, nothing cleared, snapshot dropped; the rest are resumed through
  /// [dismissAll], which finishes the capture and applies the operation.
  /// Returns how many operations were settled.
  Future<int> settleAbandonedCaptures({
    required Duration staleAfter,
    required Duration expireAfter,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT id, account_id, captured_at < now() - make_interval(secs => $2) AS expired
  FROM public.attention_clear_operation
 WHERE status = 'pending' AND capture_snapshot IS NOT NULL
   AND captured_at < now() - make_interval(secs => $1)
 ORDER BY captured_at''',
          variables: [
            Variable<double>(staleAfter.inMilliseconds / 1000),
            Variable<double>(expireAfter.inMilliseconds / 1000),
          ],
        )
        .get();
    var settled = 0;
    for (final row in rows) {
      final operationId = row.read<String>('id');
      if (row.read<bool>('expired')) {
        if (await _expireCapture(operationId)) settled++;
      } else {
        final result = await dismissAll(
          accountId: row.read<String>('account_id'),
          operationId: operationId,
        );
        if (result.status != AttentionClearStatus.pending) settled++;
      }
    }
    return settled;
  }

  Future<bool> _expireCapture(String operationId) => _database.transaction(
    () async {
      // Locks the header, and re-checks under the lock that nobody finished or
      // touched the capture since it was listed.
      final locked = await _database
          .customSelect(
            r'''
SELECT id FROM public.attention_clear_operation
 WHERE id = $1 AND status = 'pending' AND capture_snapshot IS NOT NULL
 FOR UPDATE''',
            variables: [Variable<String>(operationId)],
          )
          .getSingleOrNull();
      if (locked == null) return false;
      await _database.customUpdate(
        r'''
UPDATE public.attention_clear_operation_member
   SET state = 'skipped', skip_reason = $2
 WHERE operation_id = $1 AND state = 'pending'
''',
        variables: [
          Variable<String>(operationId),
          Variable<String>(AttentionSweepSkipReason.expired.wireName),
        ],
        updateKind: UpdateKind.update,
      );
      await _database.customUpdate(
        r'''
UPDATE public.attention_clear_operation
   SET status = $2, capture_snapshot = NULL
 WHERE id = $1''',
        variables: [
          Variable<String>(operationId),
          Variable<String>(AttentionClearStatus.expired.name),
        ],
        updateKind: UpdateKind.update,
      );
      return true;
    },
  );

  AttentionSweepResult _emptyResult(
    String operationId,
    AttentionClearStatus status,
  ) => AttentionSweepResult(
    operationId: operationId,
    appliedReceiptIds: const [],
    appliedOutcomeBeaconIds: const [],
    skipped: const [],
    failed: const [],
    pending: const [],
    status: status,
  );

  Future<({String owner, String? status})?> _operationHeader(
    String operationId,
  ) async {
    final header = await _database
        .customSelect(
          r'''
SELECT account_id, status FROM public.attention_clear_operation WHERE id = $1
''',
          variables: [Variable<String>(operationId)],
        )
        .getSingleOrNull();
    if (header == null) return null;
    return (
      owner: header.read<String>('account_id'),
      status: header.read<String?>('status'),
    );
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
        case _stateUndone:
          // U09c put it back. Reporting it as pending would make a later
          // resume claim work it will never do; reporting it as applied would
          // be a lie about the row's current state.
          skipped.add(
            AttentionSweepMember(
              kind: kind,
              id: id,
              reason: AttentionSweepSkipReason.undone,
            ),
          );
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
  static const _stateUndone = 'undone';
  static const _stateSkipped = 'skipped';
  static const _stateFailed = 'failed';
}

/// What happened to one member's restore attempt. `refusedByGuard` and
/// `databaseRefused` are kept apart on purpose: the first is this unit saying
/// no, the second is the database saying no, and only the second is a bug.
enum _RestoreOutcome { restored, refusedByGuard, databaseRefused }
