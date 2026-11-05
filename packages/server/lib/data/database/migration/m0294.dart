part of '_migrations.dart';

/// The hierarchy statement trigger runs before this row trigger. Blocks take
/// both user barriers exclusively; Post delivery takes its sender's shared.
final m0294 = Migration('0294', [
  r'''
CREATE FUNCTION public.user_block_pair_lock(p_blocker text, p_blocked text) RETURNS void
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'tentura.user_block.v1:' || least(p_blocker, p_blocked), 0));
  PERFORM pg_advisory_xact_lock(hashtextextended(
    'tentura.user_block.v1:' || greatest(p_blocker, p_blocked), 0));
END;
$$
''',
  r'''
CREATE FUNCTION public.user_block_pair_lock_row() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  PERFORM public.user_block_pair_lock(NEW.blocker_id, NEW.blocked_id);
  RETURN NEW;
END;
$$
''',
  '''
CREATE TRIGGER user_block_pair_lock_trg BEFORE INSERT ON public.user_block FOR EACH ROW EXECUTE FUNCTION public.user_block_pair_lock_row()
''',
]);
