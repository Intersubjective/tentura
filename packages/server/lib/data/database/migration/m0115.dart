part of '_migrations.dart';

/// Expands the notification outbox into the per-recipient attention-receipt
/// store while preserving every legacy write, read, dedup, and realtime path.
final m0115 = Migration('0115', [
  '''
ALTER TABLE public.notification_outbox
  ADD COLUMN seen_at              timestamptz,
  ADD COLUMN source_event_key     text,
  ADD COLUMN destination_kind     text,
  ADD COLUMN target_entity_id     text,
  ADD COLUMN presentation_key     text,
  ADD COLUMN presentation_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  ADD COLUMN in_app_preference_class text,
  ADD COLUMN suppression_class    text NOT NULL DEFAULT 'standard'
    CONSTRAINT notification_outbox__suppression_chk
    CHECK (suppression_class IN ('mandatory', 'standard', 'noisy')),
  ADD COLUMN access_policy        text NOT NULL DEFAULT 'legacy'
    CONSTRAINT notification_outbox__access_policy_chk
    CHECK (access_policy IN (
      'legacy', 'beacon_content', 'beacon_tombstone', 'recipient_safe', 'profile'
    )),
  ADD CONSTRAINT notification_outbox__preference_class_chk CHECK (
    in_app_preference_class IS NULL OR suppression_class = 'noisy'
  ),
  ADD CONSTRAINT notification_outbox__beacon_policy_chk CHECK (
    access_policy NOT IN ('beacon_content', 'beacon_tombstone') OR beacon_id IS NOT NULL
  ),
  ADD CONSTRAINT notification_outbox__recipient_safe_chk CHECK (
    access_policy <> 'recipient_safe' OR (
      presentation_key IS NOT NULL AND presentation_key IN (
        'room_member_removed', 'offer_declined', 'offer_removed'
      )
    )
  ),
  ADD CONSTRAINT notification_outbox__new_shape_chk CHECK (
    source_event_key IS NULL
    OR (destination_kind IS NOT NULL AND presentation_key IS NOT NULL)
  );
''',
  '''
CREATE INDEX notification_outbox__unread
  ON public.notification_outbox (account_id, created_at DESC, id DESC)
  WHERE COALESCE(seen_at, read_at) IS NULL;
''',
  '''
CREATE INDEX notification_outbox__feed_v2
  ON public.notification_outbox (account_id, created_at DESC, id DESC);
''',
  '''
ALTER TABLE public.notification_preference
  ADD COLUMN muted_in_app_event_classes text[] NOT NULL DEFAULT '{}';
''',
]);
