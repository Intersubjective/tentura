import 'dart:convert';

import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/trust_evidence_repository_port.dart';
import 'package:tentura_server/domain/trust/trust_bin.dart';
import 'package:tentura_server/domain/trust/trust_context.dart';
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

    for (final item in sortedItems) {
      final kind = _kindFor(item);
      if (kind == null) continue;
      await _insertLedgerRow(batch: batch, item: item, kind: kind);
    }

    // Re-fold every touched pair, also when the ledger row already existed:
    // the projection is idempotent and self-heals a wiped user_trust_edge.
    final sortedTargets = {
      for (final item in sortedItems) item.targetUserId,
    }.toList()..sort();
    for (final targetUserId in sortedTargets) {
      await _db
          .customSelect(
            r'SELECT public.trust_project_pair($1, $2)',
            variables: [
              Variable<String>(batch.sourceUserId),
              Variable<String>(targetUserId),
            ],
          )
          .getSingle();
    }
  }

  /// `trust_kind_config.kind` for [item] (m0202). Phase A has positive kinds
  /// only, so negative and no-effect evidence has no ledger row.
  static int? _kindFor(TrustEvidence item) {
    if (item.bin != TrustBin.good && item.bin != TrustBin.veryGood) {
      return null;
    }
    return switch (item.context) {
      TrustContext.personal => _kindVouch,
      TrustContext.commitment => _kindHelped,
      TrustContext.forward => _kindUsefulForward,
    };
  }

  static const _kindVouch = 1;
  static const _kindHelped = 2;
  static const _kindUsefulForward = 5;

  Future<void> _insertLedgerRow({
    required TrustEvidenceBatch batch,
    required TrustEvidence item,
    required int kind,
  }) {
    final sourceKey = [
      item.sourceType.key,
      batch.sourceUserId,
      item.targetUserId,
      item.context.key,
      item.sourceId ?? item.requestId ?? '',
    ].join(':');
    return _db.customInsert(
      r'''
INSERT INTO public.trust_evidence (
  id,
  subject_user_id,
  object_user_id,
  kind,
  count,
  source_key,
  beacon_id,
  occurred_at,
  metadata
) VALUES (gen_random_uuid()::text, $1, $2, $3, $4, $5, $6, $7, $8::jsonb)
ON CONFLICT (source_key) DO NOTHING
''',
      variables: [
        Variable<String>(batch.sourceUserId),
        Variable<String>(item.targetUserId),
        Variable<int>(kind),
        Variable<double>(item.count),
        Variable<String>(sourceKey),
        Variable<String>(item.requestId),
        Variable(PgDateTime(batch.at), PgTypes.timestampWithTimezone),
        Variable<String>(jsonEncode(item.metadata.toJson())),
      ],
    );
  }

  @override
  Future<bool> hasForwardEvidenceForRequest(String requestId) => _db
      .customSelect(
        r'''
SELECT EXISTS (
  SELECT 1 FROM public.trust_evidence
  WHERE beacon_id = $1 AND kind = 5
) AS present
''',
        variables: [Variable<String>(requestId)],
      )
      .map((r) => r.read<bool>('present'))
      .getSingle();
}
