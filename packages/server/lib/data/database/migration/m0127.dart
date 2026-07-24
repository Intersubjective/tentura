part of '_migrations.dart';

/// Close the legacy/new receipt-shape split after single-creator convergence.
final m0127 = Migration('0127', [
  r'''ALTER TABLE public.notification_outbox ALTER COLUMN access_policy DROP DEFAULT;''',
  r'''ALTER TABLE public.notification_outbox DROP CONSTRAINT notification_outbox__new_shape_chk;''',
  r'''ALTER TABLE public.notification_outbox
        DROP CONSTRAINT notification_outbox__access_policy_chk,
        ADD CONSTRAINT notification_outbox__access_policy_chk
          CHECK (access_policy = ANY (ARRAY['beacon_content','beacon_tombstone','recipient_safe','profile']));''',
  r'''ALTER TABLE public.notification_outbox ALTER COLUMN source_event_key SET NOT NULL;''',
  r'''ALTER TABLE public.notification_outbox ALTER COLUMN destination_kind SET NOT NULL;''',
  r'''ALTER TABLE public.notification_outbox ALTER COLUMN presentation_key SET NOT NULL;''',
]);
