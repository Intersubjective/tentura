part of '_migrations.dart';

/// Post draft attachments (#1236 S2): photos and files saved on a Post draft
/// before publish. Same columns as `beacon_room_message_attachment`, keyed by
/// the Post; publish moves the rows onto the root message.
final m0305 = Migration('0305', [
  '''
CREATE TABLE public.post_draft_attachment (
    id text DEFAULT concat('A', "substring"(replace((gen_random_uuid())::text, '-'::text, ''::text), 1, 12)) NOT NULL,
    beacon_id text NOT NULL,
    kind smallint NOT NULL,
    image_id uuid,
    file_url text,
    mime text DEFAULT 'application/octet-stream'::text NOT NULL,
    size_bytes bigint DEFAULT 0 NOT NULL,
    width integer,
    height integer,
    "position" smallint DEFAULT 0 NOT NULL,
    file_name text DEFAULT ''::text NOT NULL,
    CONSTRAINT post_draft_attachment_pkey PRIMARY KEY (id),
    CONSTRAINT post_draft_attachment_beacon_id_fkey FOREIGN KEY (beacon_id)
      REFERENCES public.beacon(id) ON DELETE CASCADE,
    CONSTRAINT post_draft_attachment_image_id_fkey FOREIGN KEY (image_id)
      REFERENCES public.image(id) ON DELETE SET NULL
)
''',
  '''
CREATE INDEX post_draft_attachment_beacon_idx
  ON public.post_draft_attachment (beacon_id, "position")
''',
]);
