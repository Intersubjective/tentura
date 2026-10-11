part of '_migrations.dart';

/// Budding E1 (Arch §2.4, I5): `beacon.kind` is immutable. The in-place
/// Post→Request conversion is gone (a Post buds a child Request instead), so
/// `beacon_kind_policy_guard` now rejects any kind change, in both
/// directions. The one-way forward-policy clause from m0209 is kept as is.
final m0247 = Migration('0247', [
  r'''
CREATE OR REPLACE FUNCTION public.beacon_kind_policy_guard() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF NEW.kind IS DISTINCT FROM OLD.kind THEN
    RAISE EXCEPTION 'beacon kind is immutable' USING ERRCODE = 'check_violation';
  END IF;
  IF OLD.forward_policy = 1 AND NEW.forward_policy = 0 AND OLD.status <> 3 THEN
    RAISE EXCEPTION 'forward policy is one-way' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END
$$
''',
]);
