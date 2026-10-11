part of '_migrations.dart';

/// `inbox_item_guard_tombstone` (m0193) refused every status change on a
/// tombstone row (3 closed-before-response, 4 deleted-before-response), even
/// inside the beacon trigger. That made the two beacon-trigger transitions
/// on tombstone rows unreachable:
/// - 3 → 0: reopening from review (5 → 0/7/8) reverts the open → 5
///   tombstone (`beacon_apply_inbox_before_response_tombstone`, m0213). Any
///   Request with an untouched inbox row (e.g. a forward recipient) could not
///   be reopened.
/// - 3 → 4: deleting a Request whose rows were already tombstoned
///   (docs/before-response-terminal-tombstone.md: "upgrade from 3 to 4").
///
/// Both are now allowed only under the beacon-trigger flag. Every other
/// status change, and any `rejection_message` change, on a tombstone row is
/// still refused.
final m0246 = Migration('0246', [
  r'''
CREATE OR REPLACE FUNCTION public.inbox_item_guard_tombstone() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
  allow text;
BEGIN
  allow := current_setting('tentura.allow_inbox_tombstone_transition', true);
  IF TG_OP = 'INSERT' AND NEW.status IN (3, 4) THEN
    IF allow IS DISTINCT FROM '1' THEN
      RAISE EXCEPTION 'inbox_item cannot insert tombstone status without beacon trigger';
    END IF;
  END IF;
  IF TG_OP = 'UPDATE' THEN
    IF OLD.status IN (3, 4) THEN
      IF NEW.rejection_message IS DISTINCT FROM OLD.rejection_message THEN
        RAISE EXCEPTION 'inbox_item tombstone rows cannot change status or rejection_message';
      END IF;
      IF NEW.status IS DISTINCT FROM OLD.status THEN
        -- m0246: the beacon trigger may upgrade 3 -> 4 (delete) and revert
        -- 3 -> 0 (reopen from review). Nothing else leaves a tombstone.
        IF NOT (OLD.status = 3 AND NEW.status IN (0, 4)) THEN
          RAISE EXCEPTION 'inbox_item tombstone rows cannot change status or rejection_message';
        END IF;
        IF allow IS DISTINCT FROM '1' THEN
          IF NEW.status = 4 THEN
            RAISE EXCEPTION 'inbox_item tombstone status upgrade requires beacon trigger';
          END IF;
          RAISE EXCEPTION 'inbox_item tombstone revert requires beacon trigger';
        END IF;
      END IF;
    END IF;
    -- m0183: `tombstone_dismissed_at` is no longer restricted to statuses
    -- 3 and 4. Every outcome kind carries its own dismiss control, so every
    -- outcome kind must be dismissable and un-dismissable (U09c undo).
    IF NEW.status IN (3, 4) AND OLD.status NOT IN (3, 4) THEN
      IF allow IS DISTINCT FROM '1' THEN
        RAISE EXCEPTION 'inbox_item cannot transition to tombstone status without beacon trigger';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$
''',
]);
