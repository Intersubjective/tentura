part of '_migrations.dart';

/// U05c — carry obligation identity through actor erasure.
///
/// `attention_anonymize_deleted_actor` (m0129) demotes every receipt touching
/// an erased actor to a non-obligation: it clears `requires_action`, the
/// thread key and the settlement facts, keeping the shared history readable
/// without retaining who it was about. It predates m0178's obligation
/// identity columns, so it left `logical_task_key` and
/// `lifecycle_generation` populated on a row that is no longer an
/// obligation — which `notification_outbox__logical_task_chk` forbids.
///
/// Harmless until U05c, because nothing wrote those columns. The moment
/// dispatch does, deleting a user who appears in a live obligation aborts the
/// delete. `beacon_hierarchy_child_independence_pg_test` caught it on the
/// first full sweep, from its fixture teardown.
///
/// The fix is the one line the original would have had: null the two columns
/// alongside `attention_thread_key`. The function body is otherwise m0129's
/// verbatim; `CREATE OR REPLACE` keeps the existing trigger binding.
final m0181 = Migration('0181', [
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
    logical_task_key = NULL,
    lifecycle_generation = NULL,
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
]);
