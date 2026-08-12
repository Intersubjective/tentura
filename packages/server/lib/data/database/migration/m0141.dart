part of '_migrations.dart';

/// Ledger extension for subjective help-tag evidence (unit A1).
///
/// Adds provenance FKs, source_type CHECK, partial unique indexes for
/// seed/forward/close-ack rows, and an aggregation scan index.
final m0141 = Migration('0141', [
  '''
ALTER TABLE public.person_capability_event
  ADD COLUMN forward_edge_id text NULL
      REFERENCES public.beacon_forward_edge(id) ON DELETE CASCADE,
  ADD COLUMN invitation_id text NULL
      REFERENCES public.invitation(id) ON DELETE SET NULL,
  ADD CONSTRAINT pce_source_type_ck CHECK (source_type IN (0,1,2,3,4));
''',
  '''
CREATE UNIQUE INDEX pce_seed_attestation_uq
  ON public.person_capability_event(observer_user_id, subject_user_id, tag_slug)
  WHERE source_type = 4 AND deleted_at IS NULL;
''',
  '''
CREATE UNIQUE INDEX pce_forward_reason_uq
  ON public.person_capability_event(forward_edge_id, tag_slug)
  WHERE source_type = 1 AND deleted_at IS NULL AND forward_edge_id IS NOT NULL;
''',
  '''
CREATE UNIQUE INDEX pce_close_ack_uq
  ON public.person_capability_event(observer_user_id, subject_user_id, tag_slug, beacon_id)
  WHERE source_type = 3 AND deleted_at IS NULL;
''',
  '''
CREATE INDEX pce_aggregation_idx
  ON public.person_capability_event(subject_user_id, tag_slug, observer_user_id)
  WHERE deleted_at IS NULL AND is_negative = false;
''',
]);
