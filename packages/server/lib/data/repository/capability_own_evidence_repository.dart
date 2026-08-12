import 'package:drift/drift.dart' show Variable;
import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/domain/port/capability_own_evidence_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: CapabilityOwnEvidencePort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class CapabilityOwnEvidenceRepository implements CapabilityOwnEvidencePort {
  const CapabilityOwnEvidenceRepository(this._database);

  final TenturaDb _database;

  @override
  Future<List<OwnEvidenceRow>> fetchOwnEvidence({
    required String egoId,
    required List<String> subjectIds,
    required List<String> tagSlugs,
  }) async {
    if (subjectIds.isEmpty || tagSlugs.isEmpty) return const [];

    final rows = await _database
        .customSelect(
          r'''
SELECT subject_user_id, tag_slug, source_type
FROM public.person_capability_event
WHERE observer_user_id = $1
  AND subject_user_id = ANY($2::text[])
  AND tag_slug = ANY($3::text[])
  AND deleted_at IS NULL
  AND is_negative = false
  AND source_type IN (1, 3, 4)
ORDER BY subject_user_id, tag_slug, source_type
''',
          variables: [
            Variable<String>(egoId),
            Variable<List<String>>(subjectIds, PgTypes.textArray),
            Variable<List<String>>(tagSlugs, PgTypes.textArray),
          ],
          readsFrom: {_database.personCapabilityEvents},
        )
        .get();

    return [
      for (final row in rows)
        OwnEvidenceRow(
          subjectUserId: row.read<String>('subject_user_id'),
          tagSlug: row.read<String>('tag_slug'),
          channel: _channelFromSourceType(row.read<int>('source_type')),
        ),
    ];
  }

  @override
  Future<List<TombstoneRef>> fetchTombstones({
    required String egoId,
    required List<String> subjectIds,
  }) async {
    if (subjectIds.isEmpty) return const [];

    final rows = await _database
        .customSelect(
          r'''
SELECT subject_user_id, tag_slug
FROM public.person_capability_event
WHERE observer_user_id = $1
  AND subject_user_id = ANY($2::text[])
  AND is_negative = true
  AND deleted_at IS NULL
ORDER BY subject_user_id, tag_slug
''',
          variables: [
            Variable<String>(egoId),
            Variable<List<String>>(subjectIds, PgTypes.textArray),
          ],
          readsFrom: {_database.personCapabilityEvents},
        )
        .get();

    return [
      for (final row in rows)
        TombstoneRef(
          subjectUserId: row.read<String>('subject_user_id'),
          tagSlug: row.read<String>('tag_slug'),
        ),
    ];
  }

  static EvidenceChannel _channelFromSourceType(int sourceType) => switch (sourceType) {
    3 => EvidenceChannel.outcome,
    1 || 4 => EvidenceChannel.seed,
    _ => throw StateError('unexpected source_type $sourceType'),
  };
}
