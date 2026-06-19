part of '_migrations.dart';

/// Beacon YOU responsibility counter: per-beacon items-seen watermark +
/// coordination_item.published_at for "new since last viewed" semantics.
final m0090 = Migration('0090', [
  r'''
CREATE TABLE public.beacon_items_seen (
  user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  beacon_id text NOT NULL REFERENCES public.beacon(id) ON DELETE CASCADE,
  last_seen_at timestamptz NOT NULL
);
''',
  r'''
CREATE UNIQUE INDEX uq_beacon_items_seen
  ON public.beacon_items_seen(user_id, beacon_id);
''',
  r'''
ALTER TABLE public.coordination_item
  ADD COLUMN published_at timestamptz NULL;
''',
  r'''
UPDATE public.coordination_item
  SET published_at = created_at
  WHERE published = true AND published_at IS NULL;
''',
  r'''
CREATE INDEX idx_coordination_item_published_at
  ON public.coordination_item(beacon_id, published_at)
  WHERE published = true;
''',
]);
