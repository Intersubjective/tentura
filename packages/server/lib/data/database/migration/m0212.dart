part of '_migrations.dart';

/// Post help-offer guard (plan §4): a Post (`beacon.kind = 1`) takes no help
/// offers. `beacon_help_offer_request_only` rejects the insert with
/// `check_violation`, behind the use-case guard and the Hasura insert check.
final m0212 = Migration('0212', [
  r'''
CREATE FUNCTION public.beacon_help_offer_request_only() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.beacon
    WHERE id = NEW.beacon_id AND kind = 1
  ) THEN
    RAISE EXCEPTION 'help offer on a Post is not allowed'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$
''',
  '''
CREATE TRIGGER beacon_help_offer_request_only BEFORE INSERT ON public.beacon_help_offer FOR EACH ROW EXECUTE FUNCTION public.beacon_help_offer_request_only()
''',
]);
