part of '_migrations.dart';

/// Private Request forwards waiting for a person to join Tentura.
final m0341 = Migration('0341', [
  '''
CREATE TABLE public.phantom_pending_forward (
  id text PRIMARY KEY,
  phantom_id text NOT NULL REFERENCES public.phantom (id) ON DELETE CASCADE,
  sender_id text NOT NULL REFERENCES public."user" (id) ON DELETE CASCADE,
  beacon_id text NOT NULL REFERENCES public.beacon (id) ON DELETE CASCADE,
  parent_forward_edge_id text,
  note text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  state text NOT NULL DEFAULT 'pending'
    CHECK (state IN ('pending', 'claimed', 'delivered', 'lapsed', 'offered')),
  merge_id text REFERENCES public.phantom_merge (id) ON DELETE SET NULL,
  recipient_id text REFERENCES public."user" (id) ON DELETE SET NULL,
  forward_edge_id text REFERENCES public.beacon_forward_edge (id) ON DELETE SET NULL,
  lapse_reason text,
  resolved_at timestamptz
)
''',
  '''
CREATE UNIQUE INDEX phantom_pending_forward_active_pair
ON public.phantom_pending_forward (phantom_id, beacon_id)
WHERE state IN ('pending', 'claimed')
''',
  '''
CREATE TRIGGER assert_owner_scope
BEFORE INSERT OR UPDATE ON public.phantom_pending_forward
FOR EACH ROW EXECUTE FUNCTION public.assert_owner_scope('sender_id')
''',
]);
