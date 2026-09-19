part of '_migrations.dart';

/// U11 — `placement`: where a receipt is allowed to speak (D16, R7, §8).
///
/// A child Request is its own attention object. Hierarchy lifecycle notices
/// propagated to the destination Request exist only so that Request's log
/// stays complete — they must not give it a dot, a count, or a new position.
///
/// The contract has declared `placement: timeline_only` for
/// `beaconHierarchyStatusChanged` since U03b, but nothing persisted it, so the
/// read path had no column to honour. This adds it.
///
/// It is a column rather than a read-path `event_type` test on purpose. The
/// placement of a receipt is decided **at event time by the producer**, like
/// every other projected field on this table; deriving it in SQL would put a
/// second, drifting copy of the classification in the projection and would
/// re-classify historical rows whenever the policy changed. `'primary'` is the
/// default so every pre-U11 row keeps exactly today's behaviour.
final m0189 = Migration('0189', [
  '''
ALTER TABLE public.notification_outbox
  ADD COLUMN IF NOT EXISTS placement text NOT NULL DEFAULT 'primary';
''',

  '''
ALTER TABLE public.notification_outbox
  DROP CONSTRAINT IF EXISTS notification_outbox__placement_chk;
''',

  '''
ALTER TABLE public.notification_outbox
  ADD CONSTRAINT notification_outbox__placement_chk
  CHECK (placement IN ('primary', 'timeline_only'));
''',

  // Every indicator query filters on it, and the timeline-only slice is small
  // next to the primary one, so the useful index is the partial one.
  '''
CREATE INDEX IF NOT EXISTS notification_outbox__timeline_only
  ON public.notification_outbox (account_id, beacon_id)
  WHERE placement = 'timeline_only';
''',

  '''
COMMENT ON COLUMN public.notification_outbox.placement IS
  'U11/D16 placement policy, not an attention class. ''primary'' takes part in dots, counts and ordering; ''timeline_only'' is visible and recoverable but excluded from every primary-surface indicator, so child activity never lights an ancestor Request.';
''',
]);
