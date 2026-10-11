part of '_migrations.dart';

/// #189 rev 2 — backfill the `personal` flag on existing receipts.
///
/// `AttentionPolicy.isPersonal` now writes `presentation_payload.personal` on
/// every new receipt; the For You card reads it to build its «вам» zone. This
/// gives rows written before that the same answer, from the same inputs the
/// policy uses: the event type, the recipient's event-time reasons (kept on
/// `attention_occurrence_recipient`) and a human actor other than the
/// recipient. The two lists are `AttentionPolicy.canBePersonal` and
/// `AttentionPolicy.personalRecipientReasons` as of this migration.
///
/// A receipt with no occurrence (pre-U05) stays without the flag and reads as
/// not personal. Triggers are off so the backfill does not fan out a realtime
/// change per account. Safe to replay: rows that already carry the flag are
/// skipped.
final m0237 = Migration('0237', [
  'ALTER TABLE public.notification_outbox DISABLE TRIGGER USER',

  '''
UPDATE public.notification_outbox o
SET presentation_payload = o.presentation_payload || jsonb_build_object(
  'personal',
  (o.presentation_payload ->> 'eventType') IN (
      'relayReceived', 'offerAccepted', 'offerDeclined', 'offerRemoved',
      'commitmentReleased', 'roomMessagePosted', 'postFirstResponse',
      'needsMe', 'blockerOpened', 'promiseMade', 'promiseWithdrawn',
      'commitmentAccepted', 'commitmentCancelled', 'commitmentRedirected',
      'batonAsked'
    )
    AND COALESCE(o.actor_user_id, '') <> ''
    AND o.actor_user_id <> o.account_id
    AND EXISTS (
      SELECT 1
      FROM public.attention_occurrence_recipient r
      WHERE r.occurrence_id = o.occurrence_id
        AND r.account_id = o.account_id
        AND r.reasons ?| ARRAY[
          'forwardRecipient', 'directedChatTarget', 'targetOfAsk',
          'batonCandidate', 'postAuthor', 'affectedParticipant'
        ]
    )
)
WHERE o.occurrence_id IS NOT NULL
  AND NOT (o.presentation_payload ? 'personal')
''',

  'ALTER TABLE public.notification_outbox ENABLE TRIGGER USER',
]);
