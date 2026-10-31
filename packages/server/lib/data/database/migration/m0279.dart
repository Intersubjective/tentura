part of '_migrations.dart';

/// #766 — «Seen by» on a Request's latest next-step update: when each member
/// last opened the Request view. A reader has seen the latest update when
/// their `last_seen_at` is at or after `beacon_room_state.updated_at`, so a
/// newer update starts the list over without touching these rows.
///
/// Separate from `beacon_room_seen` (the chat read watermark): opening the
/// Request is not reading its discussion. Rows go with the account and with
/// the Request.
final m0279 = Migration('0279', [
  '''
CREATE TABLE public.beacon_update_seen (
    user_id text NOT NULL
      REFERENCES public."user"(id) ON DELETE CASCADE,
    beacon_id text NOT NULL
      REFERENCES public.beacon(id) ON DELETE CASCADE,
    last_seen_at timestamp with time zone NOT NULL,
    PRIMARY KEY (user_id, beacon_id)
);
''',

  '''
CREATE INDEX beacon_update_seen_beacon_idx
  ON public.beacon_update_seen USING btree (beacon_id, last_seen_at);
''',

  '''
COMMENT ON TABLE public.beacon_update_seen IS
  'Per-member time the Request view was last opened; seen-by for the latest next-step update.';
''',
]);
