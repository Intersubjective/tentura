part of '_migrations.dart';

/// Two "what really changed" columns (#517, #361).
///
/// **Next step revision (#517).** `beacon_room_state.current_line_revision`
/// counts changes of `current_line`. `BeaconRoomNowLineUpdate` sends the
/// revision the editor opened with and the write is a compare-and-set on it,
/// so a save based on an older line is refused instead of silently replacing
/// someone else's newer one. The trigger bumps it for every writer that
/// changes the line (the room API and the legacy plan-item path alike); a save
/// of the same text changes nothing and keeps the revision. Existing rows start
/// at 0, the same value a Request without a row reads as.
///
/// **Help offer edit time (#361).** `beacon_help_offer.edited_at` is set only
/// when the helper changes the text or help types of an offer that stays
/// active (a withdrawal, removal or re-admission is not an edit; only this
/// trigger writes the column). `updated_at` moves on every write (accept
/// writes the stake/role, removal and re-admission write the status), so the
/// client could not tell an edit from an accept and marked fresh admissions
/// "edited". Existing rows stay NULL: past writes cannot be told apart, and a
/// missing "edited" mark is better than a wrong one.
final m0258 = Migration('0258', [
  '''
ALTER TABLE public.beacon_room_state
  ADD COLUMN current_line_revision integer NOT NULL DEFAULT 0
''',
  r'''
CREATE FUNCTION public.beacon_room_state_bump_line_revision() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.current_line_revision := CASE WHEN NEW.current_line = '' THEN 0 ELSE 1 END;
  ELSIF NEW.current_line IS DISTINCT FROM OLD.current_line THEN
    NEW.current_line_revision := OLD.current_line_revision + 1;
  ELSE
    NEW.current_line_revision := OLD.current_line_revision;
  END IF;
  RETURN NEW;
END;
$$
''',
  '''
CREATE TRIGGER beacon_room_state_bump_line_revision
  BEFORE INSERT OR UPDATE ON public.beacon_room_state
  FOR EACH ROW EXECUTE FUNCTION public.beacon_room_state_bump_line_revision()
''',
  '''
ALTER TABLE public.beacon_help_offer
  ADD COLUMN edited_at timestamp with time zone
''',
  r'''
CREATE FUNCTION public.beacon_help_offer_mark_edited() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  IF OLD.status = 0 AND NEW.status = 0 AND (
       NEW.message IS DISTINCT FROM OLD.message
    OR NEW.help_type IS DISTINCT FROM OLD.help_type
  ) THEN
    NEW.edited_at := now();
  ELSE
    NEW.edited_at := OLD.edited_at;
  END IF;
  RETURN NEW;
END;
$$
''',
  '''
CREATE TRIGGER beacon_help_offer_mark_edited
  BEFORE UPDATE ON public.beacon_help_offer
  FOR EACH ROW EXECUTE FUNCTION public.beacon_help_offer_mark_edited()
''',
]);
