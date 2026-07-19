import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/trust/trust_evidence.dart';

import '../database/tentura_db.dart';

@LazySingleton(
  as: TrustEvidenceRepositoryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class TrustEvidenceRepository implements TrustEvidenceRepositoryPort {
  TrustEvidenceRepository(this._db);

  final TenturaDb _db;

  @override
  Future<void> record(TrustEvidenceBatch batch) async {
    final sortedItems = [...batch.items]
      ..sort(
        (a, b) {
          final byTarget = a.targetUserId.compareTo(b.targetUserId);
          if (byTarget != 0) return byTarget;
          return a.context.key.compareTo(b.context.key);
        },
      );

    final appliedPairs = <String>{};

    for (final item in sortedItems) {
      final insertedId = await _insertLedgerRow(
        batch: batch,
        item: item,
      );
      if (insertedId == null) continue;

      await _db
          .customSelect(
            r'SELECT trust_apply_source_evidence($1, $2, $3, $4, $5)',
            variables: [
              Variable<String>(item.context.key),
              Variable<String>(batch.sourceUserId),
              Variable<String>(item.targetUserId),
              Variable<String>(item.bin.key),
              Variable<double>(item.count),
            ],
          )
          .getSingle();

      appliedPairs.add(item.targetUserId);
    }

    final sortedTargets = appliedPairs.toList()..sort();
    for (final targetUserId in sortedTargets) {
      await _db
          .customSelect(
            r'SELECT trust_rebuild_effective_edge($1, $2)',
            variables: [
              Variable<String>(batch.sourceUserId),
              Variable<String>(targetUserId),
            ],
          )
          .getSingle();
    }
  }

  Future<String?> _insertLedgerRow({
    required TrustEvidenceBatch batch,
    required TrustEvidence item,
  }) async {
    final metadataJson = jsonEncode(item.metadata.toJson());
    final row = await _db
        .customSelect(
          r'''
INSERT INTO trust_evidence_event (
  trust_context,
  subject_user_id,
  object_user_id,
  bin,
  count,
  source_type,
  source_id,
  request_id,
  occurred_at,
  metadata
) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb)
ON CONFLICT DO NOTHING
RETURNING id
''',
          variables: [
            Variable<String>(item.context.key),
            Variable<String>(batch.sourceUserId),
            Variable<String>(item.targetUserId),
            Variable<String>(item.bin.key),
            Variable<double>(item.count),
            Variable<String>(item.sourceType.key),
            item.sourceId == null
                ? const Variable<String>(null)
                : Variable<String>(item.sourceId),
            item.requestId == null
                ? const Variable<String>(null)
                : Variable<String>(item.requestId),
            Variable(PgDateTime(batch.at), PgTypes.timestampWithTimezone),
            Variable<String>(metadataJson),
          ],
        )
        .map((r) => r.read<String>('id'))
        .getSingleOrNull();
    return row;
  }

  @override
  Future<bool> hasForwardEvidenceForRequest(String requestId) => _db
      .customSelect(
        r'''
SELECT EXISTS (
  SELECT 1 FROM trust_evidence_event
  WHERE request_id = $1 AND trust_context = 'forward'
) AS present
''',
        variables: [Variable<String>(requestId)],
      )
      .map((r) => r.read<bool>('present'))
      .getSingle();
}
