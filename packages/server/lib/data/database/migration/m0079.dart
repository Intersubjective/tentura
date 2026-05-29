part of '_migrations.dart';

/// Link activity events back to their coordination item (Log row tap-to-focus).
final m0079 = Migration('0079', [
  '''
ALTER TABLE public.beacon_activity_event
  ADD COLUMN IF NOT EXISTS coordination_item_id text NULL
    REFERENCES public.coordination_item(id)
    ON UPDATE CASCADE ON DELETE SET NULL;
''',
  '''
CREATE INDEX IF NOT EXISTS beacon_activity_event_coordination_item_idx
  ON public.beacon_activity_event (coordination_item_id);
''',
]);
