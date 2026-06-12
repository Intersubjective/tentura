part of '_migrations.dart';

/// Subjective profiles: per-viewer private contact names (address-book style).
/// `user_contact` stores what `viewer_id` privately calls `subject_id`; the
/// subject must never be able to read it (table is not tracked in Hasura, all
/// access goes through viewer-scoped V2 resolvers).
/// `invitation.addressee_name` holds the name the inviter typed when creating
/// the invite; on consumption it is upserted into `user_contact` for the
/// inviter. Nullable for legacy rows; required for new invites at app level.
final m0085 = Migration('0085', [
  '''
CREATE TABLE public.user_contact (
  viewer_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  subject_id text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  contact_name text NOT NULL,
  created_at timestamptz DEFAULT now() NOT NULL,
  updated_at timestamptz DEFAULT now() NOT NULL,
  PRIMARY KEY (viewer_id, subject_id),
  CONSTRAINT user_contact__no_self CHECK (viewer_id <> subject_id),
  CONSTRAINT user_contact__contact_name_len CHECK (char_length(contact_name) <= 128)
);
''',
  '''
CREATE INDEX user_contact_subject_id ON public.user_contact USING btree (subject_id);
''',
  '''
ALTER TABLE public.invitation ADD COLUMN IF NOT EXISTS addressee_name text;
''',
  '''
ALTER TABLE public.invitation ADD CONSTRAINT invitation__addressee_name_len
  CHECK (addressee_name IS NULL OR char_length(addressee_name) <= 128);
''',
]);
