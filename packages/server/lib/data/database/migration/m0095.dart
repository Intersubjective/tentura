part of '_migrations.dart';

/// Account-scoped notification preferences + per-beacon mutes.
///
/// Push/email opt-in is stored per semantic category (text[]). Quiet hours are
/// minutes-of-day in the account's local time via tz_offset_minutes.
final m0095 = Migration('0095', [
  '''
CREATE TABLE IF NOT EXISTS public.notification_preference (
  account_id        text PRIMARY KEY REFERENCES public."user"(id) ON DELETE CASCADE,
  push_categories   text[] NOT NULL DEFAULT ARRAY['asksOfMe','unblocksMe','coordination'],
  email_categories  text[] NOT NULL DEFAULT ARRAY['asksOfMe'],
  quiet_hours_start integer,
  quiet_hours_end   integer,
  tz_offset_minutes integer NOT NULL DEFAULT 0,
  email_digest      text NOT NULL DEFAULT 'off'
                    CHECK (email_digest IN ('off','daily','weekly')),
  snooze_until      timestamptz,
  lock_screen_safe  boolean NOT NULL DEFAULT false,
  locale            text NOT NULL DEFAULT 'en',
  updated_at        timestamptz NOT NULL DEFAULT now()
);
''',
  '''
CREATE TABLE IF NOT EXISTS public.notification_beacon_mute (
  account_id  text NOT NULL REFERENCES public."user"(id) ON DELETE CASCADE,
  beacon_id   text NOT NULL REFERENCES public.beacon(id) ON DELETE CASCADE,
  muted_until timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, beacon_id)
);
''',
]);
