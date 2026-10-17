part of '_migrations.dart';

/// B077b — the helper's × on the «Your help was accepted» event sub-card,
/// kept per account so every device of that account hides it.
///
/// One row per account and Request. Only the helper writes it (through
/// `DismissOfferAccepted`, which requires an offer of theirs on the Request);
/// it carries no content and goes away with the account or the Request.
final m0252 = Migration('0252', [
  '''
CREATE TABLE public.offer_accepted_dismissal (
    user_id text NOT NULL
      REFERENCES public."user"(id) ON DELETE CASCADE,
    beacon_id text NOT NULL
      REFERENCES public.beacon(id) ON DELETE CASCADE,
    dismissed_at timestamp with time zone DEFAULT now() NOT NULL,
    PRIMARY KEY (user_id, beacon_id)
)
''',
  '''
CREATE INDEX offer_accepted_dismissal_beacon_idx
  ON public.offer_accepted_dismissal USING btree (beacon_id)
''',
  '''
COMMENT ON TABLE public.offer_accepted_dismissal IS
  'Per-account dismissal of the helper''s «offer accepted» event sub-card (B077b).'
''',
]);
