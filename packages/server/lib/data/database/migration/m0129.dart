part of '_migrations.dart';

/// Retain shared attention history when an actor is erased, but replace every
/// actor-bearing fact and presentation copy with a stable deleted-account
/// representation. This runs in the user-delete transaction so no retained
/// receipt can observe a partially scrubbed actor.
final m0129 = Migration('0129', [
  r'''
CREATE OR REPLACE FUNCTION public.attention_anonymize_deleted_actor()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  affected_occurrence_ids text[];
BEGIN
  SELECT COALESCE(array_agg(DISTINCT occurrence_id), ARRAY[]::text[])
  INTO affected_occurrence_ids
  FROM (
    SELECT occurrence.id AS occurrence_id
    FROM public.attention_occurrence occurrence
    WHERE occurrence.actor_user_id = OLD.id

    UNION ALL

    SELECT recipient.occurrence_id
    FROM public.attention_occurrence_recipient recipient
    WHERE recipient.role_facts @> jsonb_build_object('actorUserId', OLD.id)

    UNION ALL

    SELECT receipt.occurrence_id
    FROM public.notification_outbox receipt
    WHERE receipt.occurrence_id IS NOT NULL
      AND (
        receipt.actor_user_id = OLD.id
        OR receipt.presentation_payload @> jsonb_build_object('actorUserId', OLD.id)
      )

    UNION ALL

    SELECT delivery.occurrence_id
    FROM public.attention_channel_delivery delivery
    WHERE delivery.payload @> jsonb_build_object('actorUserId', OLD.id)
  ) affected;

  UPDATE public.attention_occurrence occurrence
  SET
    actor_user_id = NULL,
    source_event_key = 'erased-actor|' || occurrence.id,
    immutable_payload = jsonb_strip_nulls(jsonb_build_object(
      'kind', occurrence.immutable_payload -> 'kind',
      'priority', occurrence.immutable_payload -> 'priority',
      'title', 'Deleted account',
      'body', 'An account involved in this activity was deleted.',
      'actionUrl', '/#/'
    ))
  WHERE occurrence.id = ANY(affected_occurrence_ids);

  UPDATE public.attention_occurrence_recipient recipient
  SET
    role_facts = jsonb_build_object(
      'canReadBeaconContent',
      COALESCE(recipient.role_facts -> 'canReadBeaconContent', 'false'::jsonb)
    ),
    collapse_key = 'erased-actor|' || recipient.occurrence_id || '|'
      || recipient.account_id
  WHERE recipient.occurrence_id = ANY(affected_occurrence_ids);

  UPDATE public.notification_outbox receipt
  SET
    actor_user_id = NULL,
    title = 'Deleted account',
    body = 'An account involved in this activity was deleted.',
    action_url = '/#/',
    dedup_key = 'erased-actor|' || receipt.id,
    source_event_key = 'erased-actor|' || receipt.id,
    beacon_id = NULLIF(receipt.beacon_id, OLD.id),
    coordination_item_id = NULLIF(receipt.coordination_item_id, OLD.id),
    target_entity_id = NULLIF(receipt.target_entity_id, OLD.id),
    presentation_payload = jsonb_strip_nulls(jsonb_build_object(
      'eventType', receipt.presentation_payload ->> 'eventType'
    )),
    requires_action = false,
    attention_thread_key = NULL,
    settlement_kind = NULL,
    settled_at = NULL,
    settled_by_user_id = NULL,
    settled_by_occurrence_id = NULL
  WHERE receipt.occurrence_id = ANY(affected_occurrence_ids)
     OR receipt.actor_user_id = OLD.id
     OR receipt.presentation_payload @> jsonb_build_object('actorUserId', OLD.id);

  UPDATE public.attention_channel_delivery delivery
  SET
    payload = jsonb_build_object(
    'receiptId', delivery.receipt_id,
    'recipientId', delivery.payload -> 'recipientId',
    'kind', delivery.payload -> 'kind',
    'priority', delivery.payload -> 'priority',
    'title', 'Deleted account',
    'body', 'An account involved in this activity was deleted.',
    'actionUrl', '/#/',
    'dedupKey', 'erased-actor|' || delivery.receipt_id,
    'actorUserId', 'deleted-account',
    'reason', 'account_deleted',
    'beaconId', NULLIF(delivery.payload ->> 'beaconId', OLD.id),
    'coordinationItemId',
      NULLIF(delivery.payload ->> 'coordinationItemId', OLD.id)
    ),
    last_error = NULL
  WHERE delivery.occurrence_id = ANY(affected_occurrence_ids)
     OR delivery.payload @> jsonb_build_object('actorUserId', OLD.id);

  RETURN OLD;
END;
$$;
''',
  '''
DROP TRIGGER IF EXISTS attention_anonymize_deleted_actor_trg
  ON public."user";
''',
  '''
CREATE TRIGGER attention_anonymize_deleted_actor_trg
  BEFORE DELETE ON public."user"
  FOR EACH ROW EXECUTE FUNCTION public.attention_anonymize_deleted_actor();
''',
]);
