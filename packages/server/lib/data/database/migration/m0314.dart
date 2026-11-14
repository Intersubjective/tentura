part of '_migrations.dart';

/// Saved facts: a user's personal list of fact pointers. No foreign key on
/// `fact_card_id`, so a saved row outlives an unpinned or deleted fact and
/// reads as «No longer available».
final m0314 = Migration('0314', [
  '''
CREATE TABLE public.user_saved_fact (
  user_id text NOT NULL REFERENCES public."user"(id)
    ON UPDATE CASCADE ON DELETE CASCADE,
  fact_card_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, fact_card_id)
)
''',
  '''
CREATE INDEX user_saved_fact_user_idx
  ON public.user_saved_fact (user_id, created_at DESC)
''',
]);
