part of '_migrations.dart';

/// Beacon lineage: parent/root pointers for fork-from-beacon.
final m0087 = Migration('0087', [
  '''
ALTER TABLE public.beacon
  ADD COLUMN IF NOT EXISTS lineage_parent_beacon_id text;
''',
  '''
ALTER TABLE public.beacon
  ADD COLUMN IF NOT EXISTS lineage_root_beacon_id text;
''',
  '''
ALTER TABLE public.beacon
  ADD CONSTRAINT beacon_lineage_parent_beacon_id_fkey
    FOREIGN KEY (lineage_parent_beacon_id)
    REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE SET NULL;
''',
  '''
ALTER TABLE public.beacon
  ADD CONSTRAINT beacon_lineage_root_beacon_id_fkey
    FOREIGN KEY (lineage_root_beacon_id)
    REFERENCES public.beacon(id) ON UPDATE CASCADE ON DELETE SET NULL;
''',
  '''
CREATE INDEX IF NOT EXISTS beacon__lineage_root_beacon_id__idx
  ON public.beacon (lineage_root_beacon_id)
  WHERE lineage_root_beacon_id IS NOT NULL;
''',
]);
