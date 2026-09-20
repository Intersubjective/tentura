import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/attention/attention_policy.dart';

import 'package:tentura_server/domain/attention/attention_cutover_models.dart';
import 'package:tentura_server/domain/port/attention_cutover_port.dart';

import '../database/tentura_db.dart';
import 'attention_dismissible_sql.dart';

@LazySingleton(as: AttentionCutoverPort)
class AttentionCutoverRepository implements AttentionCutoverPort {
  const AttentionCutoverRepository(this._database);

  final TenturaDb _database;

  /// The authority on both gates. Gate 1 asks it for the key, gate 2 for the
  /// families whose placement is timeline-only — neither is re-derived here,
  /// because a second spelling of a classification is how a backfill and the
  /// write path come to disagree about the same row.
  static const _policy = AttentionPolicy();

  @override
  Future<DateTime> fixCutoverInstant() async {
    // `ON CONFLICT (id) DO NOTHING` against a one-row primary key is the whole
    // of "write it once": two isolates entering here at the same moment agree
    // on whichever instant landed first, with no read-then-write window and no
    // advisory lock. m0192's trigger is the second line of defence.
    await _database.customStatement('''
INSERT INTO public.attention_cutover (id, cutover_at)
VALUES (true, now())
ON CONFLICT (id) DO NOTHING
''');
    final at = await readCutoverInstant();
    if (at == null) {
      throw StateError('attention_cutover row missing after insert');
    }
    return at;
  }

  @override
  Future<DateTime?> readCutoverInstant() => _database
      // Read as text and parsed here: the instant is only ever reported, never
      // compared in Dart — every comparison that decides anything is the
      // `created_at < b.cutover_at` inside the batch statement, where the
      // value never leaves Postgres.
      .customSelect(
        'SELECT cutover_at::text AS cutover_at '
        'FROM public.attention_cutover WHERE id',
      )
      .map((row) => DateTime.parse(row.read<String>('cutover_at')).toUtc())
      .getSingleOrNull();

  @override
  Future<bool> isLegacySeenComplete() async {
    final done = await _database
        .customSelect('''
SELECT legacy_seen_completed_at IS NOT NULL AS done
  FROM public.attention_cutover
 WHERE id
''')
        .map((row) => row.read<bool>('done'))
        .getSingleOrNull();
    return done ?? false;
  }

  @override
  Future<AttentionCutoverBatch> convertLegacySeenBatch({
    required int batchSize,
  }) async {
    // One statement, so the conversion and the cursor that records it commit
    // together or not at all. An interruption can therefore only land on a
    // batch boundary, and a restart resumes from a cursor that never describes
    // work that did not happen.
    //
    // The `WHERE` on the UPDATE repeats the candidate predicate rather than
    // trusting the join. That repetition is the point: the not-yet-cleared
    // half of `activeOptional` is what makes a second pass over the same ids
    // change nothing, and what stops a row another writer cleared in between
    // from having its clear instant rewritten to `seen_at`.
    //
    // Both copies compose `activeOptional` rather than spelling the axis out
    // (M1, and `attention_active_attention_axis_pg_test.dart` enforces it over
    // the whole directory — in prose as well as in SQL). That is not only
    // hygiene here: it says the
    // backfill converts exactly what a surface would have called active and
    // optional, so the rows that leave the surface are the rows it cleared.
    final active = AttentionDismissibleSql.activeOptional('o');
    final row = await _database
        .customSelect(
          '''
WITH boundary AS (
  SELECT cutover_at, legacy_seen_cursor
    FROM public.attention_cutover
   WHERE id
),
candidates AS (
  SELECT o.id
    FROM public.notification_outbox o, boundary b
   WHERE $active
     AND o.seen_at IS NOT NULL
     AND o.occurrence_id IS NULL
     AND o.created_at < b.cutover_at
     AND (b.legacy_seen_cursor IS NULL OR o.id > b.legacy_seen_cursor)
   ORDER BY o.id
   LIMIT \$1
),
converted AS (
  UPDATE public.notification_outbox o
     SET cleared_at = o.seen_at,
         clear_reason = 'legacy_seen',
         cleared_by_operation_id = NULL
    FROM candidates c
   WHERE o.id = c.id
     AND $active
     AND o.seen_at IS NOT NULL
  RETURNING o.id
),
advanced AS (
  UPDATE public.attention_cutover
     SET legacy_seen_cursor = (SELECT max(id) FROM candidates)
   WHERE id AND EXISTS (SELECT 1 FROM candidates)
  RETURNING id
)
SELECT
  (SELECT count(*) FROM candidates)::int AS scanned,
  (SELECT count(*) FROM converted)::int AS converted,
  (SELECT count(*) FROM advanced)::int AS advanced
''',
          variables: [Variable<int>(batchSize)],
        )
        .getSingle();

    return AttentionCutoverBatch(
      scanned: row.read<int>('scanned'),
      converted: row.read<int>('converted'),
    );
  }

  @override
  Future<void> markLegacySeenComplete() => _database.customStatement('''
UPDATE public.attention_cutover
   SET legacy_seen_completed_at = now()
 WHERE id AND legacy_seen_completed_at IS NULL
''');

  @override
  Future<bool> isObligationKeyComplete() =>
      _isPhaseComplete('obligation_key_completed_at');

  @override
  Future<bool> isPlacementComplete() =>
      _isPhaseComplete('placement_completed_at');

  @override
  Future<void> markObligationKeyComplete() =>
      _markPhaseComplete('obligation_key_completed_at');

  @override
  Future<void> markPlacementComplete() =>
      _markPhaseComplete('placement_completed_at');

  /// U18b gate 1 — legacy obligation identity.
  ///
  /// The decision is made **in Dart, by the policy**, not in SQL. The key is
  /// `AttentionPolicy.logicalTaskKey`\'s own output over facts read from the
  /// row: a second spelling of the formula in SQL would be a key that agrees
  /// with the write path only until one of them is edited, and a key that
  /// disagrees is worse than no key at all — it points reconciliation at a
  /// task that does not exist.
  ///
  /// The candidate list is **not** filtered by derivability. Undecidable rows
  /// are scanned, counted and walked past, because nothing stored about them
  /// will become derivable later, and because `scanned` is what terminates
  /// the loop: a batch of fifty unprovable obligations has made progress.
  @override
  Future<AttentionCutoverBatch> keyLegacyObligationBatch({
    required int batchSize,
  }) {
    final live = AttentionDismissibleSql.liveObligation('o');
    return _database.transaction(() async {
      final candidates = await _database
          .customSelect(
            '''
WITH boundary AS (
  SELECT cutover_at, obligation_key_cursor
    FROM public.attention_cutover
   WHERE id
)
SELECT
  o.id AS id,
  o.account_id AS account_id,
  o.beacon_id AS beacon_id,
  o.target_entity_id AS target_entity_id,
  o.collapsed_count AS collapsed_count,
  o.presentation_payload->>\'eventType\' AS payload_event_type,
  o.presentation_payload->>\'beaconId\' AS payload_beacon_id,
  o.presentation_payload->>\'targetEntityId\' AS payload_target_entity_id,
  ao.event_type AS occurrence_event_type,
  aor.reasons::text AS reasons
  FROM public.notification_outbox o
  CROSS JOIN boundary b
  LEFT JOIN public.attention_occurrence ao
    ON ao.id = o.occurrence_id
  LEFT JOIN public.attention_occurrence_recipient aor
    ON aor.occurrence_id = o.occurrence_id
   AND aor.account_id = o.account_id
 WHERE $live
   AND o.logical_task_key IS NULL
   AND o.created_at < b.cutover_at
   AND (b.obligation_key_cursor IS NULL OR o.id > b.obligation_key_cursor)
 ORDER BY o.id
 LIMIT \$1
''',
            variables: [Variable<int>(batchSize)],
          )
          .get();
      if (candidates.isEmpty) {
        return const AttentionCutoverBatch(scanned: 0, converted: 0);
      }

      var converted = 0;
      for (final row in candidates) {
        final key = _derivedLogicalTaskKey(row);
        if (key == null) continue;
        // The `NOT EXISTS` is spelled over exactly the population of
        // `notification_outbox__live_logical_task`, so a row that would
        // collide is left unkeyed instead of raising — and stays in
        // `unrepairableObligationCount`, which is the truthful place for a
        // task whose real identity this pass cannot tell apart from another
        // row\'s. The unique index is still the backstop, not the plan.
        converted += await _database.customUpdate(
          '''
UPDATE public.notification_outbox o
   SET logical_task_key = \$2,
       lifecycle_generation = 1
 WHERE o.id = \$1
   AND $live
   AND o.logical_task_key IS NULL
   AND NOT EXISTS (
     SELECT 1
       FROM public.notification_outbox other
      WHERE other.account_id = o.account_id
        AND other.logical_task_key = \$2
        AND ${AttentionDismissibleSql.liveObligation('other')}
   )
''',
          variables: [
            Variable<String>(row.read<String>('id')),
            Variable<String>(key),
          ],
          updates: const {},
        );
      }

      await _database.customStatement(
        '''
UPDATE public.attention_cutover
   SET obligation_key_cursor = \$1
 WHERE id
''',
        [candidates.last.read<String>('id')],
      );

      return AttentionCutoverBatch(
        scanned: candidates.length,
        converted: converted,
      );
    });
  }

  /// U18b gate 2 — historical placement, for the subset that proves itself.
  ///
  /// m0189 gave every pre-existing row `\'primary\'`, so rows nobody classified
  /// claim a placement, and a `beaconHierarchyStatusChanged` receipt left
  /// `primary` can light an ancestor Request\'s dot. This demotes the rows
  /// whose family is provable and **only** those: the candidate list carries
  /// the derivability conditions itself, so an undecidable row is never even
  /// named.
  ///
  /// The families come from `AttentionPolicy.placement`, so the backfill
  /// demotes exactly what the write path would have written.
  @override
  Future<AttentionCutoverBatch> demoteLegacyPlacementBatch({
    required int batchSize,
  }) async {
    final primary = AttentionDismissibleSql.primaryPlacement('o');
    final timelineOnly = [
      for (final eventType in AttentionEventType.values)
        if (_policy.placement(eventType) == AttentionPlacement.timelineOnly)
          eventType.name,
    ].join(',');
    final row = await _database
        .customSelect(
          '''
WITH boundary AS (
  SELECT cutover_at, placement_cursor
    FROM public.attention_cutover
   WHERE id
),
candidates AS (
  SELECT o.id
    FROM public.notification_outbox o
    CROSS JOIN boundary b
    JOIN public.attention_occurrence ao
      ON ao.id = o.occurrence_id
   WHERE $primary
     AND o.created_at < b.cutover_at
     AND o.collapsed_count = 1
     AND ao.event_type = o.presentation_payload->>\'eventType\'
     AND ao.event_type = ANY (string_to_array(\$2, \',\'))
     AND (b.placement_cursor IS NULL OR o.id > b.placement_cursor)
   ORDER BY o.id
   LIMIT \$1
),
demoted AS (
  UPDATE public.notification_outbox o
     SET placement = \'timeline_only\'
    FROM candidates c
   WHERE o.id = c.id
     AND $primary
  RETURNING o.id
),
advanced AS (
  UPDATE public.attention_cutover
     SET placement_cursor = (SELECT max(id) FROM candidates)
   WHERE id AND EXISTS (SELECT 1 FROM candidates)
  RETURNING id
)
SELECT
  (SELECT count(*) FROM candidates)::int AS scanned,
  (SELECT count(*) FROM demoted)::int AS converted
''',
          variables: [
            Variable<int>(batchSize),
            Variable<String>(timelineOnly),
          ],
        )
        .getSingle();

    return AttentionCutoverBatch(
      scanned: row.read<int>('scanned'),
      converted: row.read<int>('converted'),
    );
  }

  /// The key a stored row **proves**, or `null` — which is a row left alone.
  ///
  /// Every condition here is a witness, not a heuristic:
  ///
  /// * an occurrence must exist and its `event_type` must agree with the
  ///   row\'s own payload. A single witness is not enough: the pre-U05a
  ///   collapse path repointed `occurrence_id` at the newest event, so a row
  ///   can name an occurrence that is not the event it is about;
  /// * `collapsed_count = 1`, because a collapsed row stands for several
  ///   events and the others are not necessarily of this family;
  /// * the Request must be present and agree with the payload, since it is
  ///   part of the key;
  /// * the event-time reasons come from the stored audience snapshot, never
  ///   from a plausible set invented here — they are what decides whether
  ///   this recipient owed anything at all.
  ///
  /// Anything the policy then refuses — an unknown family, an obligation
  /// variant that declares no logical-task subject, a missing subject — is a
  /// row that stays unkeyed and stays counted.
  String? _derivedLogicalTaskKey(QueryRow row) {
    final occurrenceEventType = row.readNullable<String>(
      'occurrence_event_type',
    );
    if (occurrenceEventType == null) return null;
    if (row.readNullable<String>('payload_event_type') !=
        occurrenceEventType) {
      return null;
    }
    if (row.read<int>('collapsed_count') != 1) return null;

    final beaconId = row.readNullable<String>('beacon_id');
    if (beaconId == null) return null;
    if (row.readNullable<String>('payload_beacon_id') != beaconId) return null;

    final targetEntityId = row.readNullable<String>('target_entity_id');
    if (targetEntityId != null &&
        row.readNullable<String>('payload_target_entity_id') !=
            targetEntityId) {
      return null;
    }

    final eventType = AttentionEventType.values
        .where((value) => value.name == occurrenceEventType)
        .firstOrNull;
    if (eventType == null) return null;

    final reasons = _reasons(row.readNullable<String>('reasons'));
    if (reasons == null || reasons.isEmpty) return null;

    try {
      return _policy.logicalTaskKey(
        eventType: eventType,
        recipientId: row.read<String>('account_id'),
        recipientReasons: reasons,
        role: AttentionRecipientRoleFacts(
          beaconId: beaconId,
          targetEntityId: targetEntityId,
        ),
      );
    } on ArgumentError {
      // The policy refusing to name a subject is the answer, not an error to
      // work around.
      return null;
    }
  }

  /// The stored audience snapshot, or `null` if any of it is unreadable.
  ///
  /// An unrecognised reason name makes the whole set unusable rather than a
  /// smaller one: a dropped reason can flip `requiresAction`, and a key
  /// derived from a partial audience is a guess wearing a formula.
  Set<AttentionRecipientReason>? _reasons(String? json) {
    if (json == null) return null;
    final decoded = jsonDecode(json);
    if (decoded is! List) return null;
    final reasons = <AttentionRecipientReason>{};
    for (final name in decoded) {
      final reason = AttentionRecipientReason.values
          .where((value) => value.name == name)
          .firstOrNull;
      if (reason == null) return null;
      reasons.add(reason);
    }
    return reasons;
  }

  Future<bool> _isPhaseComplete(String column) async {
    final done = await _database
        .customSelect(
          'SELECT $column IS NOT NULL AS done '
          'FROM public.attention_cutover WHERE id',
        )
        .map((row) => row.read<bool>('done'))
        .getSingleOrNull();
    return done ?? false;
  }

  Future<void> _markPhaseComplete(String column) =>
      _database.customStatement(
        'UPDATE public.attention_cutover SET $column = now() '
        'WHERE id AND $column IS NULL',
      );
}
