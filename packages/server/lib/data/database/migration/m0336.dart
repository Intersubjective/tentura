part of '_migrations.dart';

/// Owner cap lookups and relations that are removed with their person.
final m0336 = Migration('0336', [
  '''
CREATE INDEX phantom_owner_merged_at_idx ON public.phantom (owner_id, merged_at)
''',
  '''
CREATE TABLE public.phantom_tag_member (
  tag_id text NOT NULL,
  owner_id text NOT NULL,
  phantom_id text NOT NULL REFERENCES public.phantom (id) ON DELETE CASCADE,
  source smallint NOT NULL CHECK (source BETWEEN 0 AND 4),
  added_at timestamptz NOT NULL DEFAULT now(),
  membership_id uuid NOT NULL DEFAULT gen_random_uuid(),
  PRIMARY KEY (tag_id, phantom_id),
  FOREIGN KEY (tag_id, owner_id)
    REFERENCES public.person_tag (id, owner_id) ON DELETE CASCADE
)
''',
  '''
CREATE INDEX phantom_tag_member_phantom_id_idx
ON public.phantom_tag_member (phantom_id)
''',
  '''
CREATE TRIGGER assert_owner_scope
BEFORE INSERT OR UPDATE ON public.phantom_tag_member
FOR EACH ROW EXECUTE FUNCTION public.assert_owner_scope('owner_id')
''',
  '''
CREATE CONSTRAINT TRIGGER phantom_tag_member_notify_trg
AFTER INSERT OR UPDATE OR DELETE ON public.phantom_tag_member
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION public.notify_person_tag_change()
''',
  '''
ALTER TABLE public.invitation ADD COLUMN phantom_id text
  REFERENCES public.phantom (id) ON DELETE CASCADE
''',
  '''
CREATE INDEX invitation_phantom_id_idx
ON public.invitation (phantom_id) WHERE phantom_id IS NOT NULL
''',
  '''
CREATE UNIQUE INDEX invitation_one_live_per_phantom
ON public.invitation (phantom_id) WHERE phantom_id IS NOT NULL AND invited_id IS NULL
''',
]);
