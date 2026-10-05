import 'package:drift_postgres/drift_postgres.dart' show PgTypes;
import 'package:injectable/injectable.dart';

import 'package:tentura_server/consts/beacon_plan_consts.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/port/plan_attention_repository_port.dart';

import '../database/tentura_db.dart';

/// Request plan («либретто», #220) attention storage: live plan obligations,
/// their settlement, and the sweep's phase claims (m0224). Raw SQL joining
/// the caller's ambient transaction.
@Injectable(as: PlanAttentionRepositoryPort)
class PlanAttentionRepository implements PlanAttentionRepositoryPort {
  const PlanAttentionRepository(this._database);

  final TenturaDb _database;

  static final _obligationTypes = [
    AttentionEventType.planStepDue.name,
    AttentionEventType.planStepTurn.name,
    AttentionEventType.planChangePending.name,
  ];

  static DateTime? _ts(QueryRow row, String column) {
    final value = row.data[column];
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    return DateTime.tryParse(value.toString())?.toUtc();
  }

  @override
  Future<List<PlanObligationReceipt>> liveObligations(String beaconId) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT outbox.id, outbox.account_id, outbox.coordination_item_id,
       occ.event_type
FROM public.notification_outbox AS outbox
JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
WHERE outbox.beacon_id = $1
  AND outbox.requires_action
  AND outbox.settlement_kind IS NULL
  AND occ.event_type = ANY($2::text[])
ORDER BY outbox.created_at, outbox.id
''',
          variables: [
            Variable<String>(beaconId),
            Variable<List<String>>(_obligationTypes, PgTypes.textArray),
          ],
        )
        .get();
    return [
      for (final r in rows)
        PlanObligationReceipt(
          receiptId: r.read<String>('id'),
          accountId: r.read<String>('account_id'),
          eventType: attentionEventTypeFromWireName(
            r.read<String>('event_type'),
          ),
          stepId: r.readNullable<String>('coordination_item_id'),
        ),
    ];
  }

  @override
  Future<int> settle(
    Iterable<String> receiptIds, {
    required AttentionSettlementKind kind,
    String? settledByUserId,
  }) async {
    final ids = receiptIds.toSet().toList();
    if (ids.isEmpty) return 0;
    return _database.customUpdate(
      r'''
UPDATE public.notification_outbox
SET settlement_kind = $2,
    settled_at = now(),
    settled_by_user_id = $3,
    settled_by_occurrence_id = NULL
WHERE id = ANY($1::text[])
  AND requires_action
  AND settlement_kind IS NULL
''',
      variables: [
        Variable<List<String>>(ids, PgTypes.textArray),
        Variable<String>(kind.wireName),
        Variable<String>(settledByUserId),
      ],
      updateKind: UpdateKind.update,
    );
  }

  @override
  Future<bool> occurrenceExists(String sourceEventKey) async {
    final row = await _database
        .customSelect(
          r'''
SELECT EXISTS (
  SELECT 1 FROM public.attention_occurrence WHERE source_event_key = $1
) AS found
''',
          variables: [Variable<String>(sourceEventKey)],
        )
        .getSingle();
    return row.read<bool>('found');
  }

  @override
  Future<bool> claimSweepMark({
    required String key,
    required String beaconId,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
INSERT INTO public.beacon_plan_sweep_mark (key, beacon_id)
VALUES ($1, $2)
ON CONFLICT (key) DO NOTHING
RETURNING key
''',
          variables: [Variable<String>(key), Variable<String>(beaconId)],
        )
        .get();
    return rows.isNotEmpty;
  }

  @override
  Future<List<PlanSweepStep>> sweepCandidates({
    required DateTime now,
    int limit = 500,
  }) async {
    // The NOT EXISTS mirrors `PlanSweepPhase.key` for the step's last phase
    // (`authorLate` when assigned, `unassignedDue` when not): once that one
    // is claimed the step never needs the sweep again.
    final rows = await _database
        .customSelect(
          '''
SELECT ci.id, ci.beacon_id, ci.target_person_id, ci.start_at, ci.end_at,
       r.created_at AS timed_at
FROM public.coordination_item ci
JOIN public.beacon b
  ON b.id = ci.beacon_id AND b.kind = 0 AND b.status IN (0, 7, 8)
LEFT JOIN public.beacon_plan_revision r
  ON r.beacon_id = ci.beacon_id AND r.seq = ci.ack_seq
WHERE ci.kind = ${BeaconPlanConsts.stepKind}
  AND ci.status = ${BeaconPlanConsts.stepStatusLive}
  AND ci.done_at IS NULL
  AND (
    ci.start_at <= \$1::timestamptz + interval '15 minutes'
    OR ci.end_at <= \$1::timestamptz
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.beacon_plan_sweep_mark m
    WHERE m.key = 'plan_step:' || ci.id || CASE
      WHEN ci.target_person_id IS NULL THEN
        ':unassignedDue:none:'
        || floor(extract(epoch FROM COALESCE(ci.start_at, ci.end_at)) * 1000)
             ::bigint::text
      ELSE
        ':authorLate:' || ci.target_person_id || ':'
        || floor(extract(epoch FROM COALESCE(
             ci.end_at, ci.start_at + interval '15 minutes')) * 1000)
             ::bigint::text
    END
  )
ORDER BY COALESCE(ci.start_at, ci.end_at), ci.id
LIMIT \$2
''',
          variables: [
            Variable<String>(now.toUtc().toIso8601String()),
            Variable<int>(limit),
          ],
        )
        .get();
    return [
      for (final r in rows)
        PlanSweepStep(
          stepId: r.read<String>('id'),
          beaconId: r.read<String>('beacon_id'),
          assigneeId: r.readNullable<String>('target_person_id'),
          startAt: _ts(r, 'start_at'),
          endAt: _ts(r, 'end_at'),
          timedAt: _ts(r, 'timed_at'),
        ),
    ];
  }
}
