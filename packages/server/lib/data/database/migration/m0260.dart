part of '_migrations.dart';

/// Room message idempotency key (#654, #513). The client gives every send its
/// own `client_message_id` and sends it again on Retry. A send that timed out
/// may have been saved; its retry then finds the saved message by
/// `(author_id, client_message_id)` and gets it back instead of posting a
/// second copy. Keys are per author, so one person cannot claim another's.
/// Nullable: system messages, polls and older clients send none, and NULLs
/// never collide in the partial unique index.
final m0260 = Migration('0260', [
  '''
ALTER TABLE public.beacon_room_message
  ADD COLUMN client_message_id text
  CONSTRAINT beacon_room_message_client_message_id_len
    CHECK (char_length(client_message_id) BETWEEN 1 AND 64)
''',
  '''
CREATE UNIQUE INDEX beacon_room_message_author_client_message_id_key
  ON public.beacon_room_message (author_id, client_message_id)
  WHERE client_message_id IS NOT NULL
''',
]);
