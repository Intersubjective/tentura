import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/attention/attention_cutover_models.dart';
import 'package:tentura_server/domain/port/attention_cutover_port.dart';

import '../database/tentura_db.dart';

@LazySingleton(as: AttentionCutoverPort)
class AttentionCutoverRepository implements AttentionCutoverPort {
  const AttentionCutoverRepository(this._database);

  final TenturaDb _database;

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
    // trusting the join. That repetition is the point: `cleared_at IS NULL` is
    // what makes a second pass over the same ids change nothing, and what
    // stops a row another writer cleared in between from having its
    // `cleared_at` rewritten to `seen_at`.
    final row = await _database
        .customSelect(
          r'''
WITH boundary AS (
  SELECT cutover_at, legacy_seen_cursor
    FROM public.attention_cutover
   WHERE id
),
candidates AS (
  SELECT o.id
    FROM public.notification_outbox o, boundary b
   WHERE NOT o.requires_action
     AND o.seen_at IS NOT NULL
     AND o.cleared_at IS NULL
     AND o.occurrence_id IS NULL
     AND o.created_at < b.cutover_at
     AND (b.legacy_seen_cursor IS NULL OR o.id > b.legacy_seen_cursor)
   ORDER BY o.id
   LIMIT $1
),
converted AS (
  UPDATE public.notification_outbox o
     SET cleared_at = o.seen_at,
         clear_reason = 'legacy_seen',
         cleared_by_operation_id = NULL
    FROM candidates c
   WHERE o.id = c.id
     AND o.cleared_at IS NULL
     AND NOT o.requires_action
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
}
