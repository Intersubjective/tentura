part of '_migrations.dart';

/// Adds the independently monotonic settlement axis used by the separate
/// Needs you projection. Existing receipts deliberately remain non-obligations:
/// backfilling them as resolved would fabricate a domain outcome.
final m0118 = Migration('0118', [
  r'''
ALTER TABLE public.notification_outbox
  ADD COLUMN requires_action boolean NOT NULL DEFAULT false,
  ADD COLUMN attention_thread_key text,
  ADD COLUMN settlement_kind text,
  ADD COLUMN settled_at timestamptz,
  ADD COLUMN settled_by_user_id text,
  ADD COLUMN settled_by_occurrence_id text,
  ADD CONSTRAINT notification_outbox__settlement_kind_chk
    CHECK (settlement_kind IS NULL OR settlement_kind IN (
      'resolved', 'dismissed', 'superseded', 'legacy_archived'
    )),
  ADD CONSTRAINT notification_outbox__settlement_facts_chk
    CHECK (
      (settlement_kind IS NULL AND settled_at IS NULL
        AND settled_by_user_id IS NULL AND settled_by_occurrence_id IS NULL)
      OR
      (settlement_kind IS NOT NULL AND settled_at IS NOT NULL)
    ),
  ADD CONSTRAINT notification_outbox__settlement_obligation_chk
    CHECK (settlement_kind IS NULL OR requires_action),
  ADD CONSTRAINT notification_outbox__thread_key_chk
    CHECK (
      (NOT requires_action AND attention_thread_key IS NULL)
      OR (
        requires_action
        AND attention_thread_key IS NOT NULL
        AND attention_thread_key ~ '^v1\|[^|]+\|[^|]+\|[^|]+$'
        AND length(attention_thread_key) BETWEEN 5 AND 512
      )
    );
''',
  '''
CREATE INDEX notification_outbox__live_obligation
  ON public.notification_outbox (account_id, created_at DESC, id DESC)
  WHERE requires_action AND settlement_kind IS NULL;
''',
  '''
CREATE INDEX notification_outbox__live_obligation_thread
  ON public.notification_outbox (account_id, attention_thread_key)
  WHERE requires_action AND settlement_kind IS NULL
    AND attention_thread_key IS NOT NULL;
''',
]);
