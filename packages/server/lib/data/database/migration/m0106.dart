part of '_migrations.dart';

/// Invite signup genealogy: append-only edges with anonymized node keys,
/// denormalized signup timestamps (chronology CHECK), and user-delete
/// anonymization trigger.
final m0106 = Migration('0106', [
  r'''
CREATE TABLE public.invite_genealogy (
  descendant_node_key text PRIMARY KEY,
  ancestor_node_key text NOT NULL,
  descendant_user_id text UNIQUE
    REFERENCES public."user"(id) ON DELETE SET NULL,
  ancestor_user_id text
    REFERENCES public."user"(id) ON DELETE SET NULL,
  invitation_id text
    REFERENCES public.invitation(id) ON DELETE SET NULL,
  descendant_deleted_at timestamptz,
  ancestor_deleted_at timestamptz,
  ancestor_user_created_at timestamptz NOT NULL,
  descendant_user_created_at timestamptz NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT invite_genealogy__no_self CHECK (ancestor_node_key <> descendant_node_key),
  CONSTRAINT invite_genealogy__chronology CHECK (
    ancestor_user_created_at < descendant_user_created_at
  )
);
''',
  '''
CREATE INDEX invite_genealogy_ancestor_node_key
  ON public.invite_genealogy (ancestor_node_key);
''',
  '''
CREATE INDEX invite_genealogy_ancestor_user_id
  ON public.invite_genealogy (ancestor_user_id);
''',
  r'''
CREATE OR REPLACE FUNCTION public.invite_genealogy_anonymize_deleted_user()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
BEGIN
  UPDATE public.invite_genealogy
  SET
    descendant_user_id = NULL,
    descendant_deleted_at = COALESCE(descendant_deleted_at, now())
  WHERE descendant_user_id = OLD.id;

  UPDATE public.invite_genealogy
  SET
    ancestor_user_id = NULL,
    ancestor_deleted_at = COALESCE(ancestor_deleted_at, now())
  WHERE ancestor_user_id = OLD.id;

  RETURN OLD;
END;
$$;
''',
  '''
DROP TRIGGER IF EXISTS invite_genealogy_anonymize_user_trg ON public."user";
''',
  '''
CREATE TRIGGER invite_genealogy_anonymize_user_trg
  BEFORE DELETE ON public."user"
  FOR EACH ROW EXECUTE FUNCTION public.invite_genealogy_anonymize_deleted_user();
''',
]);
