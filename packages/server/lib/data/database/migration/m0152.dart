part of '_migrations.dart';

/// Lets an existing-user "handshake" accept (`bindMutual`) persist its
/// invitation row instead of deleting it, so the Invites tab can show
/// accepted-invite history alongside pending ones.
final m0152 = Migration('0152', [
  // This constraint only held because bindMutual used to delete its row;
  // once handshake accepts persist, one user can legitimately be `invited_id`
  // on many rows (one per inviter). Genealogy's own one-signup-ancestor
  // invariant (invite_genealogy.descendant_user_id UNIQUE) is independent
  // of this and is unaffected.
  r'''
ALTER TABLE public.invitation DROP CONSTRAINT invitation_invited_id_key;
''',
  // accepted_at is required because updated_at is trigger-owned
  // (set_public_invitation_updated_at fires on ANY update to this table,
  // including unrelated future edits) and cannot serve as "accepted at".
  r'''
ALTER TABLE public.invitation
  ADD COLUMN invite_origin text,
  ADD COLUMN accepted_at timestamptz;
''',
  // Backfill BEFORE adding the CHECK below. Every pre-migration row with
  // invited_id set is necessarily a signup (bindMutual's old delete-based
  // path never left a survivor). Its true accept time is its current
  // updated_at (the trigger stamped it at the moment createInvited's own
  // UPDATE ran) — captured here before anything else can overwrite
  // updated_at again.
  r'''
UPDATE public.invitation
SET invite_origin = 'new_account',
    accepted_at = updated_at
WHERE invited_id IS NOT NULL;
''',
  // Added after backfill so all existing rows already satisfy it.
  r'''
ALTER TABLE public.invitation
  ADD CONSTRAINT invitation__invite_origin_chk
    CHECK (invite_origin IN ('new_account', 'existing_account')),
  ADD CONSTRAINT invitation__accept_state_chk CHECK (
    (invited_id IS NULL AND invite_origin IS NULL AND accepted_at IS NULL)
    OR
    (invited_id IS NOT NULL AND invite_origin IS NOT NULL AND accepted_at IS NOT NULL)
  );
''',
]);
