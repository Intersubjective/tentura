part of '_migrations.dart';

/// Account erasure tombstone FKs and retained-user-reference dispositions (Task 08).
final m0157 = Migration('0157', [
  r'''
ALTER TABLE public.beacon
  DROP CONSTRAINT IF EXISTS beacon_user_id_fkey;
''',
  r'''
ALTER TABLE public.beacon
  ALTER COLUMN user_id DROP NOT NULL;
''',
  r'''
ALTER TABLE public.beacon
  ADD CONSTRAINT beacon_user_id_fkey
    FOREIGN KEY (user_id)
    REFERENCES public."user"(id)
    ON UPDATE CASCADE
    ON DELETE SET NULL;
''',
  r'''
ALTER TABLE public.beacon
  ADD CONSTRAINT beacon_owner_or_deleted_ck
    CHECK (user_id IS NOT NULL OR status = 2);
''',
  r'''
ALTER TABLE public.beacon_fact_card
  DROP CONSTRAINT IF EXISTS beacon_fact_card_pinned_by_fkey;
''',
  r'''
ALTER TABLE public.beacon_fact_card
  ALTER COLUMN pinned_by DROP NOT NULL;
''',
  r'''
ALTER TABLE public.beacon_fact_card
  ADD CONSTRAINT beacon_fact_card_pinned_by_fkey
    FOREIGN KEY (pinned_by)
    REFERENCES public."user"(id)
    ON UPDATE CASCADE
    ON DELETE SET NULL;
''',
  r'''
ALTER TABLE public.beacon_commitment_event
  DROP CONSTRAINT IF EXISTS beacon_commitment_event_actor_user_id_fkey;
''',
  r'''
ALTER TABLE public.beacon_commitment_event
  ALTER COLUMN actor_user_id DROP NOT NULL;
''',
  r'''
ALTER TABLE public.beacon_commitment_event
  ADD CONSTRAINT beacon_commitment_event_actor_user_id_fkey
    FOREIGN KEY (actor_user_id)
    REFERENCES public."user"(id)
    ON DELETE SET NULL;
''',
  r'''
ALTER TABLE public.beacon_help_offer_admission_event
  DROP CONSTRAINT IF EXISTS beacon_help_offer_admission_event_actor_user_id_fkey;
''',
  r'''
ALTER TABLE public.beacon_help_offer_admission_event
  ALTER COLUMN actor_user_id DROP NOT NULL;
''',
  r'''
ALTER TABLE public.beacon_help_offer_admission_event
  ADD CONSTRAINT beacon_help_offer_admission_event_actor_user_id_fkey
    FOREIGN KEY (actor_user_id)
    REFERENCES public."user"(id)
    ON DELETE SET NULL;
''',
  r'''
ALTER TABLE public.beacon_help_offer_coordination
  DROP CONSTRAINT IF EXISTS beacon_commitment_coordination_author_user_id_fkey;
''',
  r'''
ALTER TABLE public.beacon_help_offer_coordination
  ALTER COLUMN author_user_id DROP NOT NULL;
''',
  r'''
ALTER TABLE public.beacon_help_offer_coordination
  ADD CONSTRAINT beacon_help_offer_coordination_author_user_id_fkey
    FOREIGN KEY (author_user_id)
    REFERENCES public."user"(id)
    ON DELETE SET NULL;
''',
  r'''
ALTER TABLE public.coordination_item
  DROP CONSTRAINT IF EXISTS coordination_item_creator_id_fkey;
''',
  r'''
ALTER TABLE public.coordination_item
  ALTER COLUMN creator_id DROP NOT NULL;
''',
  r'''
ALTER TABLE public.coordination_item
  ADD CONSTRAINT coordination_item_creator_id_fkey
    FOREIGN KEY (creator_id)
    REFERENCES public."user"(id)
    ON DELETE SET NULL;
''',
  r'''
ALTER TABLE public.coordination_item
  DROP CONSTRAINT IF EXISTS coordination_item_target_person_id_fkey;
''',
  r'''
ALTER TABLE public.coordination_item
  ADD CONSTRAINT coordination_item_target_person_id_fkey
    FOREIGN KEY (target_person_id)
    REFERENCES public."user"(id)
    ON DELETE SET NULL;
''',
  r'''
ALTER TABLE public.coordination_item
  DROP CONSTRAINT IF EXISTS coordination_item_accepted_by_id_fkey;
''',
  r'''
ALTER TABLE public.coordination_item
  ADD CONSTRAINT coordination_item_accepted_by_id_fkey
    FOREIGN KEY (accepted_by_id)
    REFERENCES public."user"(id)
    ON DELETE SET NULL;
''',
]);
