import 'dart:convert';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/trust_ledger_port.dart';
import 'package:tentura_server/domain/trust/ledger_evidence.dart';

import '../database/tentura_db.dart';

@Singleton(
  as: TrustLedgerPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class TrustLedgerRepository implements TrustLedgerPort {
  const TrustLedgerRepository(this._db);

  final TenturaDb _db;

  @override
  Future<void> record(List<LedgerEvidence> evidence) async {
    if (evidence.isEmpty) return;
    await _db.customStatement(
      r'''
      INSERT INTO public.trust_evidence (
        id, subject_user_id, object_user_id, kind, count, source_key,
        beacon_id, closure_epoch, related_user_id, occurred_at, metadata
      )
      SELECT gen_random_uuid()::text, e.subject, e.object, e.kind, e.count,
        e.source_key, e.beacon_id, e.epoch, e.related_user_id,
        coalesce(e.occurred_at, now()), e.metadata
      FROM jsonb_to_recordset($1::jsonb) AS e(
        subject text, object text, kind smallint, count double precision,
        source_key text, beacon_id text, epoch integer, related_user_id text,
        occurred_at timestamptz, metadata jsonb
      )
      ON CONFLICT (source_key) DO NOTHING
      ''',
      [
        jsonEncode([
          for (final e in evidence)
            {
              'subject': e.subjectId,
              'object': e.objectId,
              'kind': e.kind.code,
              'count': e.count,
              'source_key': e.sourceKey,
              'beacon_id': e.beaconId,
              'epoch': e.epoch,
              'related_user_id': e.relatedUserId,
              'occurred_at': e.occurredAt?.toUtc().toIso8601String(),
              'metadata': e.metadata,
            },
        ]),
      ],
    );
    await project(
      {
        for (final e in evidence) (e.subjectId, e.objectId),
      }.toList(),
    );
  }

  @override
  Future<void> retract(String sourceKey) =>
      _setRetracted(sourceKey, 'now()', 'IS NULL');

  @override
  Future<void> unretract(String sourceKey) =>
      _setRetracted(sourceKey, 'NULL', 'IS NOT NULL');

  Future<void> _setRetracted(
    String sourceKey,
    String value,
    String guard,
  ) async {
    final rows = await _db
        .customSelect(
          'UPDATE public.trust_evidence SET retracted_at = $value '
          'WHERE source_key = \$1 AND retracted_at $guard '
          'RETURNING subject_user_id, object_user_id',
          variables: [Variable<String>(sourceKey)],
        )
        .get();
    await project([
      for (final r in rows)
        (r.read<String>('subject_user_id'), r.read<String>('object_user_id')),
    ]);
  }

  @override
  Future<bool> exists(String sourceKey) => _db
      .customSelect(
        'SELECT EXISTS (SELECT 1 FROM public.trust_evidence '
        r'WHERE source_key = $1) AS present',
        variables: [Variable<String>(sourceKey)],
      )
      .map((r) => r.read<bool>('present'))
      .getSingle();

  @override
  Future<bool> hasLiveUsefulForwardSince(
    String subjectId,
    String objectId,
    DateTime since,
  ) async {
    final rows = await _db
        .customSelect(
          r'''
SELECT 1 FROM public.trust_evidence
WHERE kind = 5 AND subject_user_id = $1 AND object_user_id = $2
  AND retracted_at IS NULL AND occurred_at > $3
LIMIT 1
''',
          variables: [
            Variable<String>(subjectId),
            Variable<String>(objectId),
            Variable(PgDateTime(since), PgTypes.timestampWithTimezone),
          ],
        )
        .get();
    return rows.isNotEmpty;
  }

  @override
  Future<void> lockPair(String subjectId, String objectId) => _db
      .customSelect(
        r'SELECT public.trust_pair_lock($1, $2)',
        variables: [Variable<String>(subjectId), Variable<String>(objectId)],
      )
      .get();

  @override
  Future<void> project(List<(String, String)> pairs) async {
    final sorted = {...pairs}.toList()
      ..sort((a, b) {
        final bySubject = a.$1.compareTo(b.$1);
        return bySubject != 0 ? bySubject : a.$2.compareTo(b.$2);
      });
    if (sorted.isEmpty) return;
    await _db
        .customSelect(
          r'''
      SELECT public.trust_project_pair(p.subject, p.object)
      FROM (
        SELECT subject, object
        FROM jsonb_to_recordset($1::jsonb) AS pair(subject text, object text)
        ORDER BY subject, object
      ) p
      ''',
          variables: [
            Variable<String>(
              jsonEncode([
                for (final (subject, object) in sorted)
                  {'subject': subject, 'object': object},
              ]),
            ),
          ],
        )
        .get();
  }
}
