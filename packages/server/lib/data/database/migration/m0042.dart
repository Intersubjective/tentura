part of '_migrations.dart';

/// Phase 6.1: room unread cursor per participant.
final m0042 = Migration('0042', [
  '''
ALTER TABLE public.beacon_participant
  ADD COLUMN IF NOT EXISTS last_seen_room_at timestamptz NULL;
''',
]);
