part of '_migrations.dart';

/// Acknowledgement tags as first-class evaluation state (unit C1a).
final m0145 = Migration('0145', [
  '''
CREATE TABLE public.beacon_evaluation_ack_tag (
  beacon_id text NOT NULL REFERENCES public.beacon(id) ON DELETE CASCADE,
  evaluator_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  subject_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  tag_slug text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (beacon_id, evaluator_id, subject_id, tag_slug));
''',
]);
