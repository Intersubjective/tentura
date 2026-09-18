part of '_migrations.dart';

/// U05a — makes the collapse-keyed outbox index non-unique so an in-app
/// receipt can be inserted, never rewritten.
///
/// `notification_outbox__dedup` (created by m0120 as
/// `notification_outbox__dedup_seen`, then renamed) was a **partial UNIQUE**
/// index on `(dedup_key) WHERE seen_at IS NULL`. It existed to enforce the
/// old collapse contract: at most one unseen receipt per collapse family, so
/// dispatch could keep a stable row and rewrite it in place with
/// `ON CONFLICT (dedup_key) … DO UPDATE`.
///
/// That contract is exactly what U05a retires. Two distinct occurrences in
/// one collapse family must now yield two receipts, each immutable after
/// insert, so a second unseen row per `dedup_key` is the intended state and
/// the UNIQUE index would reject it. **Do not restore the uniqueness.**
///
/// What the uniqueness is *not* load-bearing for, and must not be confused
/// with:
///
///  * **Source-event replay dedup** lives one level up, at the occurrence
///    grain: `attention_occurrence.source_event_key` is UNIQUE and dispatch
///    returns early on a matching replay without writing any receipt.
///  * **Receipt-grain idempotency** is m0178's
///    `notification_outbox__occurrence_account`, UNIQUE on
///    `(occurrence_id, account_id)`. That index, not this one, is now the
///    thing that makes a receipt exist at most once.
///
/// `dedup_key` keeps its collapse-derived value and its readers: the
/// email-marking path (`markEmailedByChannelCollapseKey`, retargeted in
/// U05b) and `markUnseen`'s unseen
/// sibling check both want *collapse-family* semantics, so the index is
/// recreated with the same columns and predicate — only the uniqueness goes.
/// Moving those paths onto a channel-level collapse key is U05b.
///
/// Plain `CREATE INDEX`, never `CONCURRENTLY`: migrant runs a migration in a
/// single transaction. Guarded by a catalogue lookup so re-running the whole
/// migration against an already-upgraded database is a no-op.
final m0179 = Migration('0179', [
  r'''
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
     WHERE i.indrelid = 'public.notification_outbox'::regclass
       AND c.relname = 'notification_outbox__dedup'
       AND i.indisunique
  ) THEN
    DROP INDEX public.notification_outbox__dedup;
  END IF;
END;
$$;
''',
  '''
CREATE INDEX IF NOT EXISTS notification_outbox__dedup
  ON public.notification_outbox (dedup_key)
  WHERE seen_at IS NULL;
''',
  '''
COMMENT ON INDEX public.notification_outbox__dedup IS
  'Lookup of unseen receipts by collapse family (email marking, unseen sibling checks). Deliberately NOT unique since U05a: two occurrences in one collapse family are two immutable receipts. Receipt-grain uniqueness is notification_outbox__occurrence_account.';
''',
]);
