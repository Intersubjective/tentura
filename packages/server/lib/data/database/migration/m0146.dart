part of '_migrations.dart';

/// Invite-seed prompt durability (unit C4).
final m0146 = Migration('0146', [
  '''
CREATE TABLE public.invite_seed_prompt_state (
  inviter_user_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  invitee_user_id text PRIMARY KEY REFERENCES public."user"(id) ON DELETE CASCADE,
  state smallint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now());
''',
]);
