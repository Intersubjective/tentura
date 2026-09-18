part of '_migrations.dart';

/// Issues #162/#180: a review package must be able to say whether it was ever
/// sent (`sent_at`), and participant context must be structured so the client
/// can localize it instead of printing server-built English.
final m0176 = Migration('0176', [
  '''
ALTER TABLE public.beacon_review_status
  ADD COLUMN IF NOT EXISTS sent_at timestamptz;
''',
  '''
UPDATE public.beacon_review_status
   SET sent_at = updated_at
 WHERE status = 2 AND sent_at IS NULL;
''',
  '''
ALTER TABLE public.beacon_evaluation_participant
  ADD COLUMN IF NOT EXISTS committed_at timestamptz,
  ADD COLUMN IF NOT EXISTS offer_message text NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS forwarder_display_name text;
''',
]);
