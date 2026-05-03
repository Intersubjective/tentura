part of '_migrations.dart';

/// `beacon_room_message.edited_at` — set on `RoomMessageEdit`; was missing from 0036 DDL.
final m0052 = Migration('0052', [
  '''
ALTER TABLE public.beacon_room_message
  ADD COLUMN IF NOT EXISTS edited_at timestamp with time zone NULL;
''',
]);
