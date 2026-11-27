part of '_migrations.dart';

final m0346 = Migration('0346', [
  '''
CREATE TABLE public.contact_check_usage (
  user_id text NOT NULL REFERENCES public."user" (id) ON DELETE CASCADE,
  day date NOT NULL,
  count integer NOT NULL CHECK (count > 0),
  PRIMARY KEY (user_id, day)
)
''',
  '''
ALTER TABLE public.phantom_import_chunk
  ADD COLUMN match_results boolean[],
  ADD CHECK (cardinality(match_results) = cardinality(created_ids))
''',
]);
