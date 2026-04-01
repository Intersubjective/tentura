part of '_migrations.dart';

/// Post-beacon evaluation (Phase 1): review windows, participants, visibility,
/// private evaluations, per-user review status.
final m0019 = Migration('0019', [
  r'''
CREATE TABLE IF NOT EXISTS public.beacon_review_window (
  beacon_id text NOT NULL,
  opened_at timestamp with time zone NOT NULL,
  closes_at timestamp with time zone NOT NULL,
  status integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT beacon_review_window_pkey PRIMARY KEY (beacon_id),
  CONSTRAINT beacon_review_window_beacon_id_fkey FOREIGN KEY (beacon_id)
    REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE
);
''',
  r'''
CREATE TABLE IF NOT EXISTS public.beacon_evaluation_participant (
  beacon_id text NOT NULL,
  user_id text NOT NULL,
  role integer NOT NULL,
  contribution_summary text NOT NULL,
  causal_hint text NOT NULL,
  CONSTRAINT beacon_evaluation_participant_pkey PRIMARY KEY (beacon_id, user_id),
  CONSTRAINT beacon_evaluation_participant_beacon_id_fkey FOREIGN KEY (beacon_id)
    REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT beacon_evaluation_participant_user_id_fkey FOREIGN KEY (user_id)
    REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE
);
''',
  r'''
CREATE TABLE IF NOT EXISTS public.beacon_evaluation_visibility (
  beacon_id text NOT NULL,
  evaluator_id text NOT NULL,
  participant_id text NOT NULL,
  CONSTRAINT beacon_evaluation_visibility_pkey PRIMARY KEY (beacon_id, evaluator_id, participant_id),
  CONSTRAINT beacon_evaluation_visibility_beacon_id_fkey FOREIGN KEY (beacon_id)
    REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT beacon_evaluation_visibility_evaluator_id_fkey FOREIGN KEY (evaluator_id)
    REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT beacon_evaluation_visibility_participant_id_fkey FOREIGN KEY (participant_id)
    REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE
);
''',
  r'''
CREATE TABLE IF NOT EXISTS public.beacon_evaluation (
  beacon_id text NOT NULL,
  evaluator_id text NOT NULL,
  evaluated_user_id text NOT NULL,
  value integer NOT NULL,
  reason_tags text NOT NULL DEFAULT '',
  note text NOT NULL DEFAULT '',
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT beacon_evaluation_pkey PRIMARY KEY (beacon_id, evaluator_id, evaluated_user_id),
  CONSTRAINT beacon_evaluation_beacon_id_fkey FOREIGN KEY (beacon_id)
    REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT beacon_evaluation_evaluator_id_fkey FOREIGN KEY (evaluator_id)
    REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT beacon_evaluation_evaluated_user_id_fkey FOREIGN KEY (evaluated_user_id)
    REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE
);
''',
  r'''
CREATE TABLE IF NOT EXISTS public.beacon_review_status (
  beacon_id text NOT NULL,
  user_id text NOT NULL,
  status integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT beacon_review_status_pkey PRIMARY KEY (beacon_id, user_id),
  CONSTRAINT beacon_review_status_beacon_id_fkey FOREIGN KEY (beacon_id)
    REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT beacon_review_status_user_id_fkey FOREIGN KEY (user_id)
    REFERENCES public."user"(id) ON UPDATE CASCADE ON DELETE CASCADE
);
''',
  r'''
CREATE INDEX IF NOT EXISTS beacon_review_window_closes_at_idx
  ON public.beacon_review_window (closes_at)
  WHERE status = 0;
''',
]);
