part of '_migrations.dart';

final m0022 = Migration('0022', [
  '''
ALTER TABLE public.beacon_commitment
  ADD COLUMN IF NOT EXISTS help_type TEXT,
  ADD COLUMN IF NOT EXISTS uncommit_reason TEXT;
''',
  '''
COMMENT ON COLUMN public.beacon_commitment.help_type IS
  'Optional help-type tag key (money, time, skill, ...)';
''',
  '''
COMMENT ON COLUMN public.beacon_commitment.uncommit_reason IS
  'Reason tag key when status=withdrawn';
''',
  '''
ALTER TABLE public.beacon
  ADD COLUMN IF NOT EXISTS coordination_status smallint NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS coordination_status_updated_at timestamptz;
''',
  '''
COMMENT ON COLUMN public.beacon.coordination_status IS
  '0=no commitments, 1=waiting for review, 2=more help needed, 3=enough help';
''',
  '''
CREATE TABLE IF NOT EXISTS public.beacon_commitment_coordination (
  commit_beacon_id text NOT NULL,
  commit_user_id text NOT NULL,
  author_user_id text NOT NULL REFERENCES public."user"(id),
  response_type smallint NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (commit_beacon_id, commit_user_id),
  CONSTRAINT beacon_commitment_coordination_commitment_fk
    FOREIGN KEY (commit_beacon_id, commit_user_id)
    REFERENCES public.beacon_commitment (beacon_id, user_id)
    ON DELETE CASCADE
);
''',
  '''
COMMENT ON TABLE public.beacon_commitment_coordination IS
  'Author per-commit coordination response; 0=useful,1=overlapping,2=need_different_skill,3=need_coordination,4=not_suitable';
''',
]);
