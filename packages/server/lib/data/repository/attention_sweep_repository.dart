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

    // Phase 2 — decide the still-pending members, a bounded batch at a time.
    //
    // Each batch is its own transaction and takes a row lock on the members it
    // is about to decide, so a concurrent twin blocks, re-reads, and finds
    // those rows no longer pending. Every member is therefore decided exactly
    // once no matter how many callers are in the loop, and both callers leave
    // only when nothing is pending — which is why they can both report the
    // same answer.
    var batches = 0;
    while (maxBatches == null || batches < maxBatches) {
      final decided = await _applyBatch(
        accountId: accountId,
        operationId: operationId,
        batchSize: bounded,
      );
      if (decided == 0) break;
      batches++;
    }

    final result = await _summarize(operationId);
    await _database.customUpdate(
      r'''
UPDATE public.attention_clear_operation
   SET status = $2, applied = $3, skipped = $4, failed = $5
 WHERE id = $1
''',
      variables: [
        Variable<String>(operationId),
        Variable<String>(result.status.name),
        Variable<int>(result.appliedCount),
        Variable<int>(result.skipped.length),
        Variable<int>(result.failed.length),
      ],
      updateKind: UpdateKind.update,
    );
    return result;
  }

  /// One batch: re-ask the dismissible question per member, then write.
  ///
  /// Re-asking is the whole point of doing this here rather than trusting the
  /// capture. A member that became ineligible in between — the forward was
  /// restored, the viewer took responsibility, another gesture got there
  /// first — is *skipped and reported*, never cleared, and never dropped
  /// silently. Returns how many members this call decided.
  Future<int> _applyBatch({
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
    if (pending.isEmpty) return 0;

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
      await _database.customUpdate(
        '''
UPDATE public.notification_outbox
   SET cleared_at = now(),
       clear_reason = 'sweep',
       cleared_by_operation_id = \$2
 WHERE account_id = \$1
   AND cleared_at IS NULL
   AND NOT requires_action
   AND id IN ($placeholders)
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

    // 4. Outcomes, one statement each inside a savepoint. The predicate is
    // the first line of defence and m0185 is the second; if the database ever
    // refuses a row this sweep thought it could dismiss, that member is
    // reported `failed` rather than taking the whole batch down with it.
    for (final id in applicableOutcomes) {
      decisions[id] = await _dismissOutcome(
        accountId: accountId,
        beaconId: id,
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

    for (final entry in decisions.entries) {
      await _database.customUpdate(
        r'''
UPDATE public.attention_clear_operation_member
   SET state = $2, skip_reason = $3
 WHERE operation_id = $1
   AND (receipt_id = $4 OR outcome_beacon_id = $4)
''',
        variables: [
          Variable<String>(operationId),
          Variable<String>(entry.value.$1),
          Variable<String>(entry.value.$2?.wireName),
          Variable<String>(entry.key),
        ],
        updateKind: UpdateKind.update,
      );
    }

    return decisions.length;
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

  Future<(String, AttentionSweepSkipReason?)> _dismissOutcome({
    required String accountId,
    required String beaconId,
  }) async {
    await _database.customStatement('SAVEPOINT attention_sweep_member');
    try {
      final rows = await _database.customUpdate(
        r'''
UPDATE public.inbox_item
   SET tombstone_dismissed_at = now()
 WHERE user_id = $1
   AND beacon_id = $2
   AND tombstone_dismissed_at IS NULL
''',
        variables: [
          Variable<String>(accountId),
          Variable<String>(beaconId),
        ],
        updateKind: UpdateKind.update,
      );
      await _database.customStatement(
        'RELEASE SAVEPOINT attention_sweep_member',
      );
      return rows > 0
          ? (_stateApplied, null)
          : (_stateSkipped, AttentionSweepSkipReason.alreadyCleared);
    } on Object {
      await _database.customStatement(
        'ROLLBACK TO SAVEPOINT attention_sweep_member',
      );
      return (_stateFailed, AttentionSweepSkipReason.refused);
    }
  }

  static String _placeholders(int count, {required int from}) =>
      List.generate(count, (index) => '\$${index + from}').join(',');

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
        final conflictTarget = isReceipt
            ? '(operation_id, receipt_id) WHERE receipt_id IS NOT NULL'
            : '(operation_id, outcome_beacon_id) '
                  'WHERE outcome_beacon_id IS NOT NULL';
        // m0186 gives each axis its own partial unique index, so the
        // conflict target has to name the axis this row is on. Both branches
        // absorb a duplicate identically — capture cannot run twice today
        // (the header insert and this loop share one transaction, so a twin's
        // `ON CONFLICT DO NOTHING` waits on the winner and then captures
        // nothing), but an insert that is idempotent on one axis and throws
        // on the other is a trap for whoever moves that boundary.
        await _database.customUpdate(
          '''
INSERT INTO public.attention_clear_operation_member
  (operation_id, receipt_id, outcome_beacon_id, beacon_id,
   outcome_generation, decision_revision, state)
VALUES (\$1, \$2, \$3, \$4, \$5, \$6, 'pending')
ON CONFLICT $conflictTarget DO NOTHING
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
