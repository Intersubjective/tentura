part of '_migrations.dart';

/// Distinguishes an original tag membership from a later re-add.
final m0337 = Migration('0337', [
  '''
ALTER TABLE public.person_tag_member
  ADD COLUMN membership_id uuid NOT NULL DEFAULT gen_random_uuid()
''',
]);
