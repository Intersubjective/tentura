part of '_migrations.dart';

/// Reconciles the deployed databases with the schema the migration chain
/// builds (drift audit, 2026-09-20 — `docs/plans/migration-squash-plan.md` §10).
///
/// Every statement here is a no-op on a database built from `m0193`. They exist
/// because `dev.tentura.io` and `ssh.tentura.io` had stamped the versions that
/// would have applied them *before* those migrations were edited in place, and
/// migrant never re-runs a stamped version. This migration is the only forward
/// path: after the squash there is no chain left to replay.
///
/// Deliberately **not** included: the row backfills the original `m0123`
/// carried (`UPDATE … SET email_digest = 'daily' WHERE email_digest = 'off'`
/// and the `array_append` of `'coordination'`). Those already ran on both
/// deployments when `0123` was the notification-preferences migration. Running
/// them again would re-subscribe every account that has since opted out through
/// `UnsubscribeCase`, which writes exactly the `'off'` this would overwrite.
/// Only the column defaults are restated.
final m0194 = Migration('0194', [
  // 1. `m0133` replaced the four-argument realtime envelope with a
  //    five-argument one carrying `p_extra` (message_id, attachment
  //    invalidation) and dropped the old signature. Databases that had already
  //    stamped `0133` when that DROP was added kept the old overload, so both
  //    deployments carry two. PostgreSQL prefers the exact-arity match, so the
  //    nine trigger functions that call it with four arguments silently get the
  //    pre-`m0133` body and never emit the extras.
  'DROP FUNCTION IF EXISTS public.emit_realtime_entity_change(text, text, text, text[]);',

  // 2. `m0007` replaced `m0003`'s trigger to also seed `user_presence`
  //    (commit 3ef84a0ab, 2025-08-13, which edited the already-shipped
  //    `m0007`). `ssh.tentura.io` still runs `m0003`'s body, so no account
  //    created there has ever had a presence row and
  //    `UserPresenceRepository` only ever issues `get`/`update` — nothing
  //    inserts one later. The body is byte-identical to `m0193`'s, so
  //    re-issuing it does not change `prosrc` on a database that is already
  //    correct.
  r'''
CREATE OR REPLACE FUNCTION public.on_user_created() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  INSERT INTO user_vsids VALUES (NEW.id, DEFAULT, DEFAULT);
  INSERT INTO user_presence (user_id) VALUES (NEW.id);
  RETURN NEW;
END;
$$;
''',

  // 3. The same backfill `m0007` ran, for the accounts created while the
  //    trigger was the `m0003` one. `user_presence` is UNLOGGED, so this is
  //    restoring current correctness, not durable state — the trigger above is
  //    what keeps it true.
  '''
INSERT INTO public.user_presence (user_id)
  SELECT id FROM public."user" ON CONFLICT (user_id) DO NOTHING;
''',

  // 4. Version `0123` used to be "default email digest on (daily) +
  //    coordination into email categories"; it was later repurposed for the
  //    beacon-visibility change that occupies it now, taking these defaults out
  //    of the chain. Both deployments kept them, and they are what
  //    `NotificationPreferencesEntity.defaults` documents, so the chain is the
  //    side that is wrong.
  '''
ALTER TABLE public.notification_preference
  ALTER COLUMN email_digest SET DEFAULT 'daily';
''',
  '''
ALTER TABLE public.notification_preference
  ALTER COLUMN email_categories
  SET DEFAULT ARRAY['asksOfMe','connections','coordination'];
''',
]);
