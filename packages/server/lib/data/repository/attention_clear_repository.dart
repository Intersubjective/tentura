import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/attention/attention_clear_models.dart';
import 'package:tentura_server/domain/port/attention_clear_port.dart';

import '../database/tentura_db.dart';
import 'attention_dismissible_sql.dart';

/// U08 — storage for the clear command.
///
/// Kept apart from `AttentionRepository` on purpose: that class is the read
/// projection and U10 rewrites it. Nothing here changes what the feed or the
/// summary return.
@Singleton(as: AttentionClearPort)
class AttentionClearRepository implements AttentionClearPort {
  const AttentionClearRepository(this._database);

  final TenturaDb _database;

  /// The optional axis (D02), behind the same authorization wall every other
  /// attention read uses. An obligation — live or settled — can never satisfy
  /// `NOT requires_action`, so it cannot enter a capture; the m0178 CHECK
  /// `notification_outbox__clear_optional_only_chk` is the second line if this
  /// predicate ever regresses.
  ///
  /// U10b: this is the same `activeOptional` function the indicators call, so
  /// what a clear may touch and what a dot counts cannot drift apart — a dot
  /// the viewer has no way to extinguish is the M1 failure seen from the
  /// other side.
  static String get _eligibleReceipts =>
      '''
SELECT receipt.id, receipt.beacon_id
  FROM public.visible_attention_receipts(\$1) visible
  JOIN public.notification_outbox receipt ON receipt.id = visible.receipt_id
 WHERE receipt.account_id = \$1
   AND ${AttentionDismissibleSql.activeOptional('receipt')}''';

  @override
  Future<AttentionClearCapture> captureEligible({
    required String accountId,
    String? beaconId,
    String? receiptId,
    int limit = AttentionClearSnapshotToken.maxMembers,
  }) async {
    final rows = await _database
        .customSelect(
          '''
$_eligibleReceipts
   AND (\$2::text IS NULL OR receipt.beacon_id = \$2)
   AND (\$3::text IS NULL OR receipt.id = \$3)
 ORDER BY receipt.created_at DESC, receipt.id DESC
 LIMIT \$4
''',
          variables: [
            Variable<String>(accountId),
            Variable<String>(beaconId),
            Variable<String>(receiptId),
            Variable<int>(
              limit.clamp(1, AttentionClearSnapshotToken.maxMembers),
            ),
          ],
        )
        .get();

    // Outcome identity at capture time. `attention_request_state` has no
    // writer yet (U09/U10 own it), so this is 0/0 for every Request today —
    // bound honestly rather than left out, so the token shape does not have to
    // change when those writers land.
    var outcomeGeneration = 0;
    var decisionRevision = 0;
    if (beaconId != null) {
      final state = await _database
          .customSelect(
            r'''
SELECT outcome_generation, decision_revision
  FROM public.attention_request_state
 WHERE account_id = $1 AND beacon_id = $2
''',
            variables: [
              Variable<String>(accountId),
              Variable<String>(beaconId),
            ],
          )
          .getSingleOrNull();
      outcomeGeneration = state?.read<int>('outcome_generation') ?? 0;
      decisionRevision = state?.read<int>('decision_revision') ?? 0;
    }

    return AttentionClearCapture(
      receiptIds: [for (final row in rows) row.read<String>('id')],
      outcomeGeneration: outcomeGeneration,
      decisionRevision: decisionRevision,
    );
  }

  @override
  Future<AttentionClearResult> apply({
    required String accountId,
    required String operationId,
    required String? beaconId,
    required AttentionClearCaptureKind kind,
    required int outcomeGeneration,
    required List<String> receiptIds,
  }) => _database.transaction(() async {
    final members = {...receiptIds};

    // 1. The operation row. `ON CONFLICT DO NOTHING` is the whole idempotency
    // story: a concurrent twin blocks on the primary key until this
    // transaction commits, then falls through to the replay path below and
    // reads the membership this one wrote.
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
        Variable<String>(beaconId == null ? kind.wireName : 'beacon:$beaconId'),
      ],
      updateKind: UpdateKind.insert,
    );

    if (inserted == 0) {
      return _replay(
        accountId: accountId,
        operationId: operationId,
        requestedIds: members,
      );
    }

    // 2. Re-authorize. Ownership and eligibility are two different answers:
    // a receipt this account owns but may no longer read is *skipped*, while
    // an id that resolves to no receipt of this account is *denied* — and an
    // id belonging to somebody else resolves to nothing here either, so the
    // two are indistinguishable from outside.
    final owned = <String, String?>{};
    final eligible = <String>{};
    if (members.isNotEmpty) {
      final placeholders = List.generate(
        members.length,
        (index) => '\$${index + 2}',
      ).join(',');
      final variables = [
        Variable<String>(accountId),
        for (final id in members) Variable<String>(id),
      ];
      final ownedRows = await _database.customSelect(
        '''
SELECT id, beacon_id FROM public.notification_outbox
 WHERE account_id = \$1 AND id IN ($placeholders)
''',
        variables: variables,
      ).get();
      for (final row in ownedRows) {
        owned[row.read<String>('id')] = row.read<String?>('beacon_id');
      }
      final beaconIndex = members.length + 2;
      final eligibleRows = await _database
          .customSelect(
            '''
$_eligibleReceipts
   AND receipt.id IN ($placeholders)
   AND (\$$beaconIndex::text IS NULL OR receipt.beacon_id = \$$beaconIndex)
''',
            variables: [...variables, Variable<String>(beaconId)],
          )
          .get();
      for (final row in eligibleRows) {
        eligible.add(row.read<String>('id'));
      }
    }

    final applied = [
      for (final id in members)
        if (eligible.contains(id)) id,
    ]..sort();
    final skipped = [
      for (final id in members)
        if (!eligible.contains(id) && owned.containsKey(id)) id,
    ]..sort();
    final denied = [
      for (final id in members)
        if (!owned.containsKey(id)) id,
    ]..sort();

    // 3. Membership, captured once. The `ON CONFLICT` target names the
    // partial index predicate because m0183 replaced the member primary key
    // with two partial UNIQUE indexes — `receipt_id` became nullable so that
    // U09b can record an outcome member, which has no receipt at all. The
    // guarantee is unchanged: one row per (operation, receipt).
    //
    // Denied ids remain deliberately absent: they are not this account's
    // receipts, so there is nothing to record, and the member table's FK
    // would refuse an id that names no receipt at all.
    for (final id in [...applied, ...skipped]) {
      await _database.customUpdate(
        r'''
INSERT INTO public.attention_clear_operation_member
  (operation_id, receipt_id, beacon_id, outcome_generation, state)
VALUES ($1, $2, $3, $4, $5)
ON CONFLICT (operation_id, receipt_id)
  WHERE receipt_id IS NOT NULL DO NOTHING
''',
        variables: [
          Variable<String>(operationId),
          Variable<String>(id),
          Variable<String>(owned[id]),
          Variable<int>(outcomeGeneration),
          Variable<String>(
            eligible.contains(id) ? _stateApplied : _stateSkipped,
          ),
        ],
        updateKind: UpdateKind.insert,
      );
    }

    // 4. The clear itself. Every clear is operation-backed: the operation row
    // is what makes this replayable and what U09's undo will unwind.
    if (applied.isNotEmpty) {
      final placeholders = List.generate(
        applied.length,
        (index) => '\$${index + 4}',
      ).join(',');
      await _database.customUpdate(
        '''
UPDATE public.notification_outbox outbox
   SET cleared_at = now(),
       clear_reason = \$2,
       cleared_by_operation_id = \$3
 WHERE outbox.account_id = \$1
   AND ${AttentionDismissibleSql.activeOptional('outbox')}
   AND outbox.id IN ($placeholders)
''',
        variables: [
          Variable<String>(accountId),
          Variable<String>(kind.wireName),
          Variable<String>(operationId),
          for (final id in applied) Variable<String>(id),
        ],
        updateKind: UpdateKind.update,
      );
    }

    final status = _statusOf(
      applied: applied,
      skipped: skipped,
      denied: denied,
    );
    await _database.customUpdate(
      r'''
UPDATE public.attention_clear_operation
   SET status = $2, applied = $3, skipped = $4, failed = 0
 WHERE id = $1
''',
      variables: [
        Variable<String>(operationId),
        Variable<String>(status.name),
        Variable<int>(applied.length),
        Variable<int>(skipped.length),
      ],
      updateKind: UpdateKind.update,
    );

    return AttentionClearResult(
      operationId: operationId,
      appliedReceiptIds: applied,
      skippedReceiptIds: skipped,
      deniedReceiptIds: denied,
      status: status,
    );
  });

  /// The answer of an operation that has already been applied.
  ///
  /// Rebuilt from the stored membership, never from the token: a replay must
  /// not clear more than the first apply did, even if the caller hands over a
  /// token that has grown since.
  Future<AttentionClearResult> _replay({
    required String accountId,
    required String operationId,
    required Set<String> requestedIds,
  }) async {
    final header = await _database
        .customSelect(
          r'''
SELECT account_id FROM public.attention_clear_operation WHERE id = $1
''',
          variables: [Variable<String>(operationId)],
        )
        .getSingleOrNull();
    if (header == null || header.read<String>('account_id') != accountId) {
      // Another account's operation id. Say nothing about it.
      return AttentionClearResult(
        operationId: operationId,
        appliedReceiptIds: const [],
        skippedReceiptIds: const [],
        deniedReceiptIds: [...requestedIds]..sort(),
        status: AttentionClearStatus.denied,
      );
    }

    final rows = await _database
        .customSelect(
          r'''
SELECT receipt_id, state FROM public.attention_clear_operation_member
 WHERE operation_id = $1
''',
          variables: [Variable<String>(operationId)],
        )
        .get();
    final applied = <String>[];
    final skipped = <String>[];
    for (final row in rows) {
      final id = row.read<String>('receipt_id');
      if (row.read<String>('state') == _stateApplied) {
        applied.add(id);
      } else {
        skipped.add(id);
      }
    }
    applied.sort();
    skipped.sort();
    final denied = [
      for (final id in requestedIds)
        if (!applied.contains(id) && !skipped.contains(id)) id,
    ]..sort();

    return AttentionClearResult(
      operationId: operationId,
      appliedReceiptIds: applied,
      skippedReceiptIds: skipped,
      deniedReceiptIds: denied,
      status: _statusOf(applied: applied, skipped: skipped, denied: denied),
    );
  }

  static AttentionClearStatus _statusOf({
    required List<String> applied,
    required List<String> skipped,
    required List<String> denied,
  }) {
    if (applied.isNotEmpty) {
      return skipped.isEmpty && denied.isEmpty
          ? AttentionClearStatus.complete
          : AttentionClearStatus.partial;
    }
    if (denied.isNotEmpty) return AttentionClearStatus.denied;
    if (skipped.isNotEmpty) return AttentionClearStatus.stale;
    return AttentionClearStatus.complete;
  }

  static const _stateApplied = 'applied';
  static const _stateSkipped = 'skipped';
}
