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
    for (final e in evidence) {
      await _db.customInsert(
        r'''
INSERT INTO public.trust_evidence (
  id, subject_user_id, object_user_id, kind, count, source_key,
  beacon_id, closure_epoch, related_user_id, occurred_at, metadata
) VALUES (
  gen_random_uuid()::text, $1, $2, $3, $4, $5, $6, $7, $8,
  coalesce($9, now()), $10::jsonb
)
ON CONFLICT (source_key) DO NOTHING
''',
        variables: [
          Variable<String>(e.subjectId),
          Variable<String>(e.objectId),
          Variable<int>(e.kind.code),
          Variable<double>(e.count),
          Variable<String>(e.sourceKey),
          Variable<String>(e.beaconId),
          Variable<int>(e.epoch),
          Variable<String>(e.relatedUserId),
          Variable(
            e.occurredAt == null ? null : PgDateTime(e.occurredAt!),
            PgTypes.timestampWithTimezone,
          ),
          Variable<String>(jsonEncode(e.metadata)),
        ],
      );
    }
    await project({
      for (final e in evidence) (e.subjectId, e.objectId),
    }.toList());
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
    for (final (s, o) in sorted) {
      await _db
          .customSelect(
            r'SELECT public.trust_project_pair($1, $2)',
            variables: [Variable<String>(s), Variable<String>(o)],
          )
          .get();
    }
  }
}
