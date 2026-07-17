part of '_migrations.dart';

/// Durable occurrence, audience-snapshot, and channel-delivery topology.
final m0121 = Migration('0121', [
  '''
CREATE TABLE public.attention_occurrence (
  id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  source_event_key text NOT NULL UNIQUE,
  event_type text NOT NULL,
  actor_user_id text,
  immutable_payload jsonb NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now()
);
''',
  '''
CREATE TABLE public.attention_occurrence_recipient (
  occurrence_id text NOT NULL REFERENCES public.attention_occurrence(id) ON DELETE RESTRICT,
  account_id text NOT NULL REFERENCES public."user"(id) ON DELETE RESTRICT,
  reasons jsonb NOT NULL,
  role_facts jsonb NOT NULL,
  collapse_key text NOT NULL,
  channel_eligible boolean NOT NULL,
  PRIMARY KEY (occurrence_id, account_id)
);
''',
  '''
ALTER TABLE public.notification_outbox
  ADD COLUMN occurrence_id text REFERENCES public.attention_occurrence(id) ON DELETE RESTRICT;
''',
  '''
CREATE INDEX notification_outbox__occurrence
  ON public.notification_outbox (occurrence_id)
  WHERE occurrence_id IS NOT NULL;
''',
  '''
CREATE TABLE public.attention_channel_delivery (
  id text PRIMARY KEY DEFAULT gen_random_uuid()::text,
  occurrence_id text NOT NULL REFERENCES public.attention_occurrence(id) ON DELETE RESTRICT,
  receipt_id text NOT NULL REFERENCES public.notification_outbox(id) ON DELETE RESTRICT,
  account_id text NOT NULL REFERENCES public."user"(id) ON DELETE RESTRICT,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'leased', 'delivered', 'dead')),
  attempts integer NOT NULL DEFAULT 0 CHECK (attempts >= 0),
  available_at timestamptz NOT NULL DEFAULT now(),
  lease_owner text,
  lease_until timestamptz,
  delivered_at timestamptz,
  dead_lettered_at timestamptz,
  last_error text,
  payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (occurrence_id, account_id),
  CHECK ((status = 'leased') = (lease_owner IS NOT NULL AND lease_until IS NOT NULL)),
  CHECK ((status = 'delivered') = (delivered_at IS NOT NULL)),
  CHECK ((status = 'dead') = (dead_lettered_at IS NOT NULL))
);
''',
  '''
CREATE INDEX attention_channel_delivery__due
  ON public.attention_channel_delivery (available_at, created_at, id)
  WHERE status IN ('pending', 'leased');
''',
  '''
CREATE TABLE public.attention_channel_throttle (
  account_id text NOT NULL REFERENCES public."user"(id) ON DELETE RESTRICT,
  channel text NOT NULL,
  lease_until timestamptz NOT NULL,
  PRIMARY KEY (account_id, channel)
);
''',
]);
