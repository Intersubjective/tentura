part of '_migrations.dart';

/// Durable per-recipient notification log backing the in-app Notification
/// Center and the email digest. Notifications were previously ephemeral FCM
/// sends; this is the pull-based ground truth.
final m0096 = Migration('0096', [
  '''
CREATE TABLE IF NOT EXISTS public.notification_outbox (
  id                   text PRIMARY KEY,
  account_id           text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  category             text NOT NULL,
  kind                 text NOT NULL,
  beacon_id            text,
  coordination_item_id text,
  actor_user_id        text,
  title                text NOT NULL,
  body                 text NOT NULL,
  action_url           text NOT NULL,
  priority             text NOT NULL,
  created_at           timestamptz NOT NULL DEFAULT now(),
  read_at              timestamptz,
  dedup_key            text NOT NULL,
  collapsed_count      integer NOT NULL DEFAULT 1,
  emailed_at           timestamptz,
  digested_at          timestamptz
);
''',
  '''
CREATE INDEX IF NOT EXISTS notification_outbox__feed
  ON public.notification_outbox (account_id, created_at DESC);
''',
  '''
CREATE INDEX IF NOT EXISTS notification_outbox__pending_email
  ON public.notification_outbox (account_id, created_at)
  WHERE emailed_at IS NULL;
''',
  '''
CREATE UNIQUE INDEX IF NOT EXISTS notification_outbox__dedup
  ON public.notification_outbox (dedup_key)
  WHERE read_at IS NULL;
''',
]);
