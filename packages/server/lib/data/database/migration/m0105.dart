part of '_migrations.dart';

/// Repair DBs where stale `on_public_user_update` was re-applied after m0006
/// (e.g. manual `sql/triggers.sql`). That trigger referenced dropped columns
/// `has_picture`, `blur_hash`, `pic_height`, `pic_width`.
final m0105 = Migration('0105', [
  '''
DROP TRIGGER IF EXISTS on_public_user_update ON public."user";
''',
  '''
DROP FUNCTION IF EXISTS public.on_public_user_update();
''',
  '''
CREATE OR REPLACE TRIGGER set_public_user_updated_at
  BEFORE UPDATE ON public."user"
  FOR EACH ROW EXECUTE FUNCTION public.set_current_timestamp_updated_at();
''',
]);
