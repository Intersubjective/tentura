import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/consts/beacon_fact_card_consts.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/domain/port/saved_fact_repository_port.dart';

import '../database/tentura_db.dart';

@LazySingleton(as: SavedFactRepositoryPort)
class SavedFactRepository implements SavedFactRepositoryPort {
  const SavedFactRepository(this._db);

  final TenturaDb _db;

  /// One transaction under a per-user advisory lock, so two concurrent saves
  /// cannot both pass the cap count.
  @override
  Future<bool> save({
    required String userId,
    required String factCardId,
    required int cap,
  }) => _db.withMutatingUser(userId, () async {
    await _db.customStatement(
      r"SELECT pg_advisory_xact_lock(hashtext('user_saved_fact:' || $1))",
      [userId],
    );
    final row = await _db
        .customSelect(
          r'''
WITH ins AS (
  INSERT INTO public.user_saved_fact (user_id, fact_card_id)
  SELECT $1::text, $2::text
  WHERE (
    SELECT count(*) FROM public.user_saved_fact WHERE user_id = $1::text
  ) < $3::integer
  ON CONFLICT (user_id, fact_card_id) DO NOTHING
  RETURNING 1
)
SELECT EXISTS (SELECT 1 FROM ins) OR EXISTS (
  SELECT 1 FROM public.user_saved_fact
  WHERE user_id = $1::text AND fact_card_id = $2::text
) AS saved
''',
          variables: [
            Variable<String>(userId),
            Variable<String>(factCardId),
            Variable<int>(cap),
          ],
        )
        .getSingle();
    return row.read<bool>('saved');
  });

  @override
  Future<void> unsave({
    required String userId,
    required String factCardId,
  }) async {
    await (_db.delete(_db.userSavedFacts)..where(
          (t) => t.userId.equals(userId) & t.factCardId.equals(factCardId),
        ))
        .go();
  }

  /// One query; `beacon_fact_access` runs once per distinct beacon, then is
  /// joined to the rows. Same rule as `SavedFactCase.save`: request-visible
  /// needs `can_read`, discussion-only `can_use_room`, removed never; a draft
  /// is author-only.
  @override
  Future<List<Map<String, Object?>>> list({required String userId}) async {
    final rows = await _db.customSelect(
      '''
WITH s AS (
  SELECT fact_card_id, created_at FROM public.user_saved_fact
  WHERE user_id = \$1::text
),
f AS (
  SELECT s.fact_card_id, c.beacon_id, c.status, c.visibility,
         COALESCE(r.fact_text, c.fact_text) AS head_text,
         COALESCE(r.attachments_json::text, '[]') AS attachments_json
  FROM s
  JOIN public.beacon_fact_card c ON c.id = s.fact_card_id
  LEFT JOIN public.beacon_fact_card_revision r
    ON r.fact_card_id = c.id AND r.seq = c.revision_seq
),
$_factAccessCte,
res AS (
  SELECT s.fact_card_id, s.created_at, f.beacon_id, acc.kind, f.head_text,
         f.attachments_json,
         $_factReadable AS available
  FROM s
  LEFT JOIN f ON f.fact_card_id = s.fact_card_id
  LEFT JOIN acc ON acc.beacon_id = f.beacon_id
)
SELECT fact_card_id, available,
       CASE WHEN available THEN beacon_id END AS beacon_id,
       CASE WHEN available THEN kind END AS kind,
       CASE WHEN available THEN head_text END AS head_text,
       CASE WHEN available THEN attachments_json END AS attachments_json
FROM res
ORDER BY created_at DESC, fact_card_id
''',
      variables: _factAccessVariables(userId),
    ).get();
    return [
      for (final row in rows)
        {
          'factCardId': row.read<String>('fact_card_id'),
          'available': row.read<bool>('available'),
          'beaconId': row.readNullable<String>('beacon_id'),
          'beaconKind': row.readNullable<int>('kind'),
          'factText': row.readNullable<String>('head_text'),
          'attachmentsJson': row.readNullable<String>('attachments_json'),
        },
    ];
  }

  /// One query over the candidate set only (plan P1): facts of beacons the
  /// user authors, stewards or is a participant of (`room_access <> 5`), plus
  /// the user's saved facts. Each word must occur in the folded head text;
  /// rows failing the same read rule as [list] are dropped.
  @override
  Future<List<Map<String, Object?>>> search({
    required String userId,
    required List<String> words,
    required int limit,
    String? excludeBeaconId,
  }) async {
    final rows = await _db
        .customSelect(
          '''
WITH b AS (
  SELECT id FROM public.beacon WHERE user_id = \$1::text
  UNION SELECT beacon_id FROM public.beacon_steward WHERE user_id = \$1::text
  UNION SELECT beacon_id FROM public.beacon_participant
    WHERE user_id = \$1::text AND room_access <> ${RoomAccessBits.left}
),
cand AS (
  SELECT c.id FROM public.beacon_fact_card c JOIN b ON b.id = c.beacon_id
  UNION SELECT fact_card_id FROM public.user_saved_fact WHERE user_id = \$1::text
),
f AS (
  SELECT c.id AS fact_card_id, c.beacon_id, c.status, c.visibility,
         c.updated_at, s.created_at AS saved_at,
         COALESCE(r.fact_text, c.fact_text) AS head_text,
         COALESCE(r.attachments_json::text, '[]') AS attachments_json
  FROM cand
  JOIN public.beacon_fact_card c ON c.id = cand.id
  LEFT JOIN public.beacon_fact_card_revision r
    ON r.fact_card_id = c.id AND r.seq = c.revision_seq
  LEFT JOIN public.user_saved_fact s
    ON s.fact_card_id = c.id AND s.user_id = \$1::text
  WHERE c.beacon_id IS DISTINCT FROM \$5::text
    AND NOT EXISTS (
      SELECT 1 FROM unnest(\$4::text[]) word
      WHERE strpos(replace(lower(COALESCE(r.fact_text, c.fact_text)),
                           'ё', 'е'), word) = 0
    )
),
$_factAccessCte
SELECT f.fact_card_id, f.beacon_id, acc.kind, f.head_text,
       f.attachments_json, f.saved_at IS NOT NULL AS saved
FROM f JOIN acc ON acc.beacon_id = f.beacon_id
WHERE $_factReadable
ORDER BY f.saved_at DESC NULLS LAST, f.updated_at DESC, f.fact_card_id
LIMIT \$6::integer
''',
          variables: [
            ..._factAccessVariables(userId),
            Variable(TypedValue(Type.textArray, words)),
            Variable<String>(excludeBeaconId),
            Variable<int>(limit),
          ],
        )
        .get();
    return [
      for (final row in rows)
        {
          'factCardId': row.read<String>('fact_card_id'),
          'beaconId': row.read<String>('beacon_id'),
          'beaconKind': row.read<int>('kind'),
          'factText': row.read<String>('head_text'),
          'attachmentsJson': row.read<String>('attachments_json'),
          'saved': row.read<bool>('saved'),
        },
    ];
  }
}

/// `acc`: `beacon_fact_access` once per distinct beacon of CTE `f`, for the
/// user in `$1`.
const _factAccessCte = r'''
acc AS MATERIALIZED (
  SELECT d.beacon_id, a.kind, a.is_draft, a.can_read, a.can_use_room,
         b.user_id = $1::text AS is_author
  FROM (SELECT DISTINCT beacon_id FROM f) d
  CROSS JOIN LATERAL public.beacon_fact_access(d.beacon_id, $1::text) a
  LEFT JOIN public.beacon b ON b.id = d.beacon_id
)''';

/// The fact read rule (plan §4.4) over `f` and `acc`: removed never, a draft
/// author-only, request-visible needs `can_read`, discussion-only
/// `can_use_room`. Uses `$2` (removed status) and `$3` (public visibility).
const _factReadable = r'''
COALESCE(
  f.status <> $2::integer
  AND (NOT acc.is_draft OR acc.is_author)
  AND CASE WHEN f.visibility = $3::integer
           THEN acc.can_read ELSE acc.can_use_room END,
  false)''';

/// `$1`..`$3` of [_factAccessCte] and [_factReadable].
List<Variable<Object>> _factAccessVariables(String userId) => [
  Variable<String>(userId),
  const Variable<int>(BeaconFactCardStatusBits.removed),
  const Variable<int>(BeaconFactCardVisibilityBits.public),
];
