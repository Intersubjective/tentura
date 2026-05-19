part of '_migrations.dart';

/// Rename orientation string column (not coordination Plan).
final m0077 = Migration('0077', [
  '''
ALTER TABLE public.beacon_room_state
  RENAME COLUMN current_plan TO current_line;
''',
]);
