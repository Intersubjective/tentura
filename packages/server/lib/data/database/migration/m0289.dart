part of '_migrations.dart';

/// Cache the shared Request-card/Field unread count plan. Keeping the SQL
/// function non-inline avoids planning all room subqueries in every Field
/// refresh, even when the unopened-item branch supplies the flag directly.
final m0289 = Migration('0289', [
  '''
CREATE FUNCTION public.request_unread_message_count(p_viewer text, p_beacon text)
RETURNS integer
LANGUAGE sql STABLE
SET search_path TO public, pg_temp
AS \$\$
SELECT ${requestUnreadMessageCountBodySql(viewer: 'p_viewer', beaconId: 'p_beacon')}
\$\$
''',
]);
