part of '_migrations.dart';

/// Replaces per-row notification invalidations with one account-scoped hint
/// per statement, then aligns the new seen axis with legacy read state.
final m0116 = Migration('0116', [
  r'''
CREATE OR REPLACE FUNCTION public.notify_notification_outbox_insert()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  affected_account_id text;
BEGIN
  FOR affected_account_id IN
    SELECT DISTINCT account_id
    FROM new_rows
    WHERE account_id IS NOT NULL AND account_id <> ''
    ORDER BY account_id
  LOOP
    PERFORM public.emit_realtime_entity_change(
      'notification',
      affected_account_id,
      'insert',
      ARRAY[affected_account_id]
    );
  END LOOP;
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING
      'notify_notification_outbox_insert failed without aborting write: %',
      SQLERRM;
    RETURN NULL;
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_notification_outbox_update()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  affected_account_id text;
BEGIN
  FOR affected_account_id IN
    WITH changed_rows AS (
      SELECT old_row.account_id AS old_account_id,
             new_row.account_id AS new_account_id
      FROM old_rows old_row
      FULL OUTER JOIN new_rows new_row ON new_row.id = old_row.id
      WHERE ROW(
        old_row.id,
        old_row.account_id,
        old_row.category,
        old_row.kind,
        old_row.priority,
        old_row.title,
        old_row.body,
        old_row.action_url,
        old_row.created_at,
        old_row.read_at,
        old_row.collapsed_count,
        old_row.beacon_id,
        old_row.coordination_item_id,
        old_row.actor_user_id,
        old_row.seen_at,
        old_row.source_event_key,
        old_row.destination_kind,
        old_row.target_entity_id,
        old_row.presentation_key,
        old_row.presentation_payload,
        old_row.in_app_preference_class,
        old_row.suppression_class,
        old_row.access_policy
      ) IS DISTINCT FROM ROW(
        new_row.id,
        new_row.account_id,
        new_row.category,
        new_row.kind,
        new_row.priority,
        new_row.title,
        new_row.body,
        new_row.action_url,
        new_row.created_at,
        new_row.read_at,
        new_row.collapsed_count,
        new_row.beacon_id,
        new_row.coordination_item_id,
        new_row.actor_user_id,
        new_row.seen_at,
        new_row.source_event_key,
        new_row.destination_kind,
        new_row.target_entity_id,
        new_row.presentation_key,
        new_row.presentation_payload,
        new_row.in_app_preference_class,
        new_row.suppression_class,
        new_row.access_policy
      )
    ),
    affected_accounts AS (
      SELECT old_account_id AS account_id FROM changed_rows
      UNION
      SELECT new_account_id AS account_id FROM changed_rows
    )
    SELECT account_id
    FROM affected_accounts
    WHERE account_id IS NOT NULL AND account_id <> ''
    ORDER BY account_id
  LOOP
    PERFORM public.emit_realtime_entity_change(
      'notification',
      affected_account_id,
      'update',
      ARRAY[affected_account_id]
    );
  END LOOP;
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING
      'notify_notification_outbox_update failed without aborting write: %',
      SQLERRM;
    RETURN NULL;
END;
$$;
''',
  r'''
CREATE OR REPLACE FUNCTION public.notify_notification_outbox_delete()
  RETURNS trigger
  LANGUAGE plpgsql
  AS $$
DECLARE
  affected_account_id text;
BEGIN
  FOR affected_account_id IN
    SELECT DISTINCT account_id
    FROM old_rows
    WHERE account_id IS NOT NULL AND account_id <> ''
    ORDER BY account_id
  LOOP
    PERFORM public.emit_realtime_entity_change(
      'notification',
      affected_account_id,
      'delete',
      ARRAY[affected_account_id]
    );
  END LOOP;
  RETURN NULL;
EXCEPTION
  WHEN OTHERS THEN
    RAISE WARNING
      'notify_notification_outbox_delete failed without aborting write: %',
      SQLERRM;
    RETURN NULL;
END;
$$;
''',
  '''
DROP TRIGGER IF EXISTS notification_outbox_entity_notify
  ON public.notification_outbox;
''',
  '''
CREATE TRIGGER notification_outbox_insert_notify
  AFTER INSERT ON public.notification_outbox
  REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.notify_notification_outbox_insert();
''',
  '''
CREATE TRIGGER notification_outbox_update_notify
  AFTER UPDATE ON public.notification_outbox
  REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.notify_notification_outbox_update();
''',
  '''
CREATE TRIGGER notification_outbox_delete_notify
  AFTER DELETE ON public.notification_outbox
  REFERENCING OLD TABLE AS old_rows
  FOR EACH STATEMENT
  EXECUTE FUNCTION public.notify_notification_outbox_delete();
''',
  '''
UPDATE public.notification_outbox
SET seen_at = read_at
WHERE seen_at IS NULL AND read_at IS NOT NULL;
''',
]);
