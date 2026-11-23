part of '_migrations.dart';

/// Direct blocks can remove votes created by existing-account invitations
/// while preserving votes that were cast independently or predate attribution.
final m0331 = Migration('0331', [
  '''
ALTER TABLE public.vote_user
  ADD COLUMN from_existing_invite boolean NOT NULL DEFAULT false,
  ADD CONSTRAINT vote_user_existing_invite_positive_ck
    CHECK (NOT from_existing_invite OR amount = 1)
''',
  r'''
CREATE FUNCTION public.vote_user_mark_explicit() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  NEW.from_existing_invite := false;
  RETURN NEW;
END;
$$
''',
  '''
CREATE TRIGGER vote_user_mark_explicit_trg
BEFORE UPDATE OF amount ON public.vote_user
FOR EACH ROW EXECUTE FUNCTION public.vote_user_mark_explicit()
''',
]);
