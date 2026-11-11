part of '_migrations.dart';

/// Forward policy stays one-way once an open Post's root message commits.
/// A root-less open Post (failed delivery, being recovered) has reached
/// nobody, so the author may still close forwarding before the retry.
/// Everything else of `beacon_kind_policy_guard` is m0247 unchanged.
final m0308 = Migration('0308', [
  r'''
CREATE OR REPLACE FUNCTION public.beacon_kind_policy_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.kind IS DISTINCT FROM OLD.kind THEN
    RAISE EXCEPTION 'beacon kind is immutable' USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.forward_policy = 1 AND NEW.forward_policy = 0 AND OLD.status <> 3
     AND NOT (OLD.kind = 1 AND OLD.status = 0 AND OLD.post_root_message_id IS NULL) THEN
    RAISE EXCEPTION 'forward policy is one-way' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END
$$
''',
]);
