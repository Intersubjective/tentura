part of '_migrations.dart';

/// Allow beacon.state 5–6 (closed review open / complete); m0015 capped at 4.
final m0020 = Migration('0020', [
  r'''
ALTER TABLE public.beacon
  DROP CONSTRAINT IF EXISTS beacon_state_range;
''',
  r'''
ALTER TABLE public.beacon
  ADD CONSTRAINT beacon_state_range
  CHECK (state >= 0 AND state <= 6);
''',
]);
