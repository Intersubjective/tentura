import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/capability/capability_event_source.dart';
import 'package:tentura_server/domain/port/capability_telemetry_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: CapabilityTelemetryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class CapabilityTelemetryRepository implements CapabilityTelemetryPort {
  const CapabilityTelemetryRepository(this._database);

  final TenturaDb _database;

  static final _seedSourceTypes = [
    CapabilityEventSource.forwardReason.dbValue,
    CapabilityEventSource.seedRoutingAttestation.dbValue,
  ];

  @override
  Future<({int seedTriples, int renewed})> countSeedRenewal() async {
    final seedTypes = _seedSourceTypes.join(',');
    final forwardReason = CapabilityEventSource.forwardReason.dbValue;

    final row = await _database
        .customSelect(
          '''
WITH seed_triples AS (
  SELECT
    observer_user_id,
    subject_user_id,
    tag_slug,
    MIN(created_at) AS earliest_seed_at
  FROM public.person_capability_event
  WHERE deleted_at IS NULL
    AND is_negative = false
    AND source_type IN ($seedTypes)
  GROUP BY observer_user_id, subject_user_id, tag_slug
),
with_expiry AS (
  SELECT
    st.observer_user_id,
    st.subject_user_id,
    st.tag_slug,
    st.earliest_seed_at,
    cee.next_expiry_at
  FROM seed_triples st
  LEFT JOIN public.capability_evidence_edge cee
    ON cee.observer_user_id = st.observer_user_id
    AND cee.subject_user_id = st.subject_user_id
    AND cee.tag_slug = st.tag_slug
),
renewed AS (
  SELECT DISTINCT
    wt.observer_user_id,
    wt.subject_user_id,
    wt.tag_slug
  FROM with_expiry wt
  WHERE EXISTS (
    SELECT 1
    FROM public.person_capability_event pce
    WHERE pce.observer_user_id = wt.observer_user_id
      AND pce.subject_user_id = wt.subject_user_id
      AND pce.tag_slug = wt.tag_slug
      AND pce.source_type = $forwardReason
      AND pce.deleted_at IS NULL
      AND pce.is_negative = false
      AND pce.created_at > wt.earliest_seed_at
      AND (
        wt.next_expiry_at IS NULL
        OR pce.created_at < wt.next_expiry_at
      )
  )
)
SELECT
  (SELECT COUNT(*)::int FROM seed_triples) AS seed_triples,
  (SELECT COUNT(*)::int FROM renewed) AS renewed
''',
          readsFrom: {
            _database.personCapabilityEvents,
            _database.capabilityEvidenceEdges,
          },
        )
        .getSingle();

    return (
      seedTriples: row.read<int>('seed_triples'),
      renewed: row.read<int>('renewed'),
    );
  }
}
