/// The Field-open fact is independent of an unseated reader's room cursor.
/// Parameters are the reader ($1) and the Request ($2).
const recordUnseatedFieldOpenSql = r'''
INSERT INTO public.beacon_field_seen (user_id, beacon_id)
SELECT $1, $2
WHERE public.beacon_can_read_content($2, $1)
  AND NOT public.beacon_effective_admission($2, $1)
ON CONFLICT (user_id, beacon_id) DO NOTHING
''';
