import 'package:drift/drift.dart' show Variable;
import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/domain/capability/capability_consts.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/port/capability_cell_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: CapabilityCellPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class CapabilityCellRepository implements CapabilityCellPort {
  const CapabilityCellRepository(this._database);

  final TenturaDb _database;

  static final _hlOut = kCapHalfLifeOutSeconds.toDouble();
  static final _hlSeed = kCapHalfLifeSeedSeconds.toDouble();

  @override
  Future<List<WitnessCellRow>> fetchCells({
    required List<String> subjectIds,
    required List<String> tagSlugs,
    required List<WitnessWeight> admittedWitnesses,
  }) async {
    if (subjectIds.isEmpty ||
        tagSlugs.isEmpty ||
        admittedWitnesses.isEmpty) {
      return const [];
    }

    final witnessIds = admittedWitnesses.map((w) => w.witnessUserId).toList();
    final mByWitness = {
      for (final w in admittedWitnesses) w.witnessUserId: w.m,
    };

    final staleTriples = await _selectStaleTriples(
      witnessIds: witnessIds,
      subjectIds: subjectIds,
      tagSlugs: tagSlugs,
    );
    for (final triple in staleTriples) {
      await rebuildCell(
        CellRef(
          observerUserId: triple.observer,
          subjectUserId: triple.subject,
          tagSlug: triple.tag,
        ),
      );
    }

    final rows = await _database
        .customSelect(
          r'''
SELECT
  c.observer_user_id,
  c.subject_user_id,
  c.tag_slug,
  public.cap_strength(c.s_out, $4::double precision, c.anchor_at, $5::double precision)
    AS e_out,
  public.cap_strength(c.s_seed, $6::double precision, c.anchor_at, $7::double precision)
    AS e_seed
FROM public.capability_evidence_edge AS c
WHERE c.observer_user_id = ANY($1::text[])
  AND c.subject_user_id = ANY($2::text[])
  AND c.tag_slug = ANY($3::text[])
''',
          variables: [
            Variable(TypedValue(Type.textArray, witnessIds)),
            Variable(TypedValue(Type.textArray, subjectIds)),
            Variable(TypedValue(Type.textArray, tagSlugs)),
            Variable<double>(kCapKOut),
            Variable<double>(_hlOut),
            Variable<double>(kCapKSeed),
            Variable<double>(_hlSeed),
          ],
        )
        .get();

    return [
      for (final row in rows)
        WitnessCellRow(
          observerUserId: row.read<String>('observer_user_id'),
          subjectUserId: row.read<String>('subject_user_id'),
          tagSlug: row.read<String>('tag_slug'),
          eOut: row.read<double>('e_out'),
          eSeed: row.read<double>('e_seed'),
          m: mByWitness[row.read<String>('observer_user_id')] ?? 0,
        ),
    ];
  }

  Future<List<({String observer, String subject, String tag})>> _selectStaleTriples({
    required List<String> witnessIds,
    required List<String> subjectIds,
    required List<String> tagSlugs,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
SELECT
  c.observer_user_id,
  c.subject_user_id,
  c.tag_slug
FROM public.capability_evidence_edge AS c
LEFT JOIN public.capability_evidence_generation AS g
  ON g.observer_user_id = c.observer_user_id
 AND g.subject_user_id = c.subject_user_id
 AND g.tag_slug = c.tag_slug
WHERE c.observer_user_id = ANY($1::text[])
  AND c.subject_user_id = ANY($2::text[])
  AND c.tag_slug = ANY($3::text[])
  AND (
    c.built_from_gen <> coalesce(g.generation, 0::bigint)
    OR (c.next_expiry_at IS NOT NULL AND c.next_expiry_at <= now())
  )
''',
          variables: [
            Variable(TypedValue(Type.textArray, witnessIds)),
            Variable(TypedValue(Type.textArray, subjectIds)),
            Variable(TypedValue(Type.textArray, tagSlugs)),
          ],
        )
        .get();

    return [
      for (final row in rows)
        (
          observer: row.read<String>('observer_user_id'),
          subject: row.read<String>('subject_user_id'),
          tag: row.read<String>('tag_slug'),
        ),
    ];
  }

  @override
  Future<void> rebuildCell(CellRef ref) => _database.customStatement(
    r'''
SELECT public.cap_cell_rebuild(
  $1, $2, $3, $4::integer, $5::double precision, $6::double precision
)
''',
    [
      ref.observerUserId,
      ref.subjectUserId,
      ref.tagSlug,
      kCapWindowMonths,
      _hlOut,
      _hlSeed,
    ],
  );

  @override
  Future<List<CellRef>> claimExpiredCells({
    required int limit,
    required String leaseOwner,
  }) async {
    final rows = await _database
        .customSelect(
          r'''
WITH due AS (
  SELECT observer_user_id, subject_user_id, tag_slug
  FROM public.capability_evidence_edge
  WHERE next_expiry_at IS NOT NULL
    AND next_expiry_at <= now()
    AND (sweep_lease_until IS NULL OR sweep_lease_until < now())
  ORDER BY next_expiry_at
  FOR UPDATE SKIP LOCKED
  LIMIT $2
)
UPDATE public.capability_evidence_edge AS c
SET sweep_lease_owner = $1,
    sweep_lease_until = now() + interval '5 minutes'
FROM due AS d
WHERE (c.observer_user_id, c.subject_user_id, c.tag_slug)
      = (d.observer_user_id, d.subject_user_id, d.tag_slug)
RETURNING c.observer_user_id, c.subject_user_id, c.tag_slug
''',
          variables: [
            Variable<String>(leaseOwner),
            Variable<int>(limit),
          ],
        )
        .get();

    return [
      for (final row in rows)
        CellRef(
          observerUserId: row.read<String>('observer_user_id'),
          subjectUserId: row.read<String>('subject_user_id'),
          tagSlug: row.read<String>('tag_slug'),
        ),
    ];
  }

  @override
  Future<void> releaseSweepLease({
    required CellRef ref,
    required String leaseOwner,
  }) => _database.customUpdate(
    r'''
UPDATE public.capability_evidence_edge
SET sweep_lease_owner = NULL,
    sweep_lease_until = NULL
WHERE observer_user_id = $1
  AND subject_user_id = $2
  AND tag_slug = $3
  AND sweep_lease_owner = $4
''',
    variables: [
      Variable<String>(ref.observerUserId),
      Variable<String>(ref.subjectUserId),
      Variable<String>(ref.tagSlug),
      Variable<String>(leaseOwner),
    ],
    updateKind: UpdateKind.update,
  );

  @override
  Future<int> gcOrphanGenerations({int limit = 100}) async {
    final candidates = await _database
        .customSelect(
          r'''
SELECT g.observer_user_id, g.subject_user_id, g.tag_slug
FROM public.capability_evidence_generation AS g
WHERE NOT EXISTS (
  SELECT 1
  FROM public.person_capability_event AS e
  WHERE e.observer_user_id = g.observer_user_id
    AND e.subject_user_id = g.subject_user_id
    AND e.tag_slug = g.tag_slug
    AND e.deleted_at IS NULL
)
AND NOT EXISTS (
  SELECT 1
  FROM public.capability_evidence_edge AS c
  WHERE c.observer_user_id = g.observer_user_id
    AND c.subject_user_id = g.subject_user_id
    AND c.tag_slug = g.tag_slug
)
ORDER BY g.observer_user_id, g.subject_user_id, g.tag_slug
LIMIT $1
''',
          variables: [Variable<int>(limit)],
        )
        .get();

    var deleted = 0;
    for (final row in candidates) {
      final observer = row.read<String>('observer_user_id');
      final subject = row.read<String>('subject_user_id');
      final tag = row.read<String>('tag_slug');
      final removed = await _database.transaction(() async {
        await _database.customStatement(
          r'SELECT public.cap_cell_lock($1, $2, $3)',
          [observer, subject, tag],
        );

        return _database.customUpdate(
          r'''
DELETE FROM public.capability_evidence_generation AS g
WHERE g.observer_user_id = $1
  AND g.subject_user_id = $2
  AND g.tag_slug = $3
  AND NOT EXISTS (
    SELECT 1
    FROM public.person_capability_event AS e
    WHERE e.observer_user_id = g.observer_user_id
      AND e.subject_user_id = g.subject_user_id
      AND e.tag_slug = g.tag_slug
      AND e.deleted_at IS NULL
  )
  AND NOT EXISTS (
    SELECT 1
    FROM public.capability_evidence_edge AS c
    WHERE c.observer_user_id = g.observer_user_id
      AND c.subject_user_id = g.subject_user_id
      AND c.tag_slug = g.tag_slug
  )
''',
          variables: [
            Variable<String>(observer),
            Variable<String>(subject),
            Variable<String>(tag),
          ],
          updateKind: UpdateKind.delete,
        );
      });
      deleted += removed;
    }
    return deleted;
  }

  @override
  Future<DateTime?> nextExpiryAt(CellRef ref) async {
    final row = await _database
        .customSelect(
          r'''
SELECT next_expiry_at
FROM public.capability_evidence_edge
WHERE observer_user_id = $1
  AND subject_user_id = $2
  AND tag_slug = $3
''',
          variables: [
            Variable<String>(ref.observerUserId),
            Variable<String>(ref.subjectUserId),
            Variable<String>(ref.tagSlug),
          ],
        )
        .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return DateTime.parse(row.read<String>('next_expiry_at')).toUtc();
  }
}
