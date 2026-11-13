part of '_migrations.dart';

/// Fact copies: `beacon_fact_card` records where a copy came from (all three
/// origin columns or none, no FK so provenance outlives the source), a beacon
/// holds one live copy per origin, origin is write-once, and a revision may
/// have kind 4 (copied).
final m0312 = Migration('0312', [
  '''
ALTER TABLE public.beacon_fact_card
  ADD COLUMN origin_fact_card_id text,
  ADD COLUMN origin_revision_seq integer,
  ADD COLUMN origin_beacon_kind smallint,
  ADD CONSTRAINT beacon_fact_card_origin_ck CHECK (
    (origin_fact_card_id IS NULL AND origin_revision_seq IS NULL
      AND origin_beacon_kind IS NULL)
    OR (origin_fact_card_id IS NOT NULL
        AND origin_revision_seq IS NOT NULL AND origin_revision_seq >= 1
        AND origin_beacon_kind IS NOT NULL
        AND origin_beacon_kind IN (0, 1))
  )
''',
  '''
CREATE UNIQUE INDEX beacon_fact_card_one_live_copy_idx
  ON public.beacon_fact_card (beacon_id, origin_fact_card_id)
  WHERE origin_fact_card_id IS NOT NULL AND status IN (0, 1)
''',
  r'''
CREATE FUNCTION public.beacon_fact_card_origin_write_once() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  RAISE EXCEPTION 'beacon_fact_card origin columns are write-once'
    USING ERRCODE = 'P0001';
END;
$$
''',
  '''
CREATE TRIGGER beacon_fact_card_origin_write_once
  BEFORE UPDATE ON public.beacon_fact_card
  FOR EACH ROW
  WHEN (
    OLD.origin_fact_card_id IS DISTINCT FROM NEW.origin_fact_card_id
    OR OLD.origin_revision_seq IS DISTINCT FROM NEW.origin_revision_seq
    OR OLD.origin_beacon_kind IS DISTINCT FROM NEW.origin_beacon_kind
  )
  EXECUTE FUNCTION public.beacon_fact_card_origin_write_once()
''',
  '''
ALTER TABLE public.beacon_fact_card_revision
  DROP CONSTRAINT IF EXISTS beacon_fact_card_revision_kind_check,
  ADD CONSTRAINT beacon_fact_card_revision_kind_check
    CHECK (kind IN (0, 1, 2, 3, 4))
''',
]);
