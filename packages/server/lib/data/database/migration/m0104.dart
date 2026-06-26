part of '_migrations.dart';

/// Align `polling_act` primary key with the Drift model and voting logic.
///
/// m0004 created the PK as (author_id, polling_id), which allows only a single
/// row per voter per poll. Multiple- and range-type polls store one row per
/// chosen variant, and the repository upserts range votes with
/// `insertOnConflictUpdate` (ON CONFLICT (author_id, polling_variant_id) …).
/// Without a unique constraint on that pair PostgreSQL raises 42P10, and
/// multi-variant votes collide on the old PK (23505). Re-key on
/// (author_id, polling_variant_id) so a voter can hold one row per variant.
final m0104 = Migration('0104', [
  '''
ALTER TABLE public.polling_act DROP CONSTRAINT polling_act__pkey;
''',
  '''
ALTER TABLE public.polling_act ADD CONSTRAINT polling_act__pkey
  PRIMARY KEY (author_id, polling_variant_id);
''',
]);
