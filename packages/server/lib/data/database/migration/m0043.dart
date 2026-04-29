part of '_migrations.dart';

/// Fix `substring(..., '\\w{12}')` defaults from m0036: that form is positional
/// `substring(text, int)`, not regex — suffix was empty so every row used id `P`/`R`/etc.
final m0043 = Migration('0043', [
  '''
ALTER TABLE public.beacon_participant
  ALTER COLUMN id SET DEFAULT concat(
    'P', substring(replace(gen_random_uuid()::text, '-', ''), 1, 12)
  );
''',
  '''
ALTER TABLE public.beacon_room_message
  ALTER COLUMN id SET DEFAULT concat(
    'R', substring(replace(gen_random_uuid()::text, '-', ''), 1, 12)
  );
''',
  '''
ALTER TABLE public.beacon_room_message_reaction
  ALTER COLUMN id SET DEFAULT concat(
    'E', substring(replace(gen_random_uuid()::text, '-', ''), 1, 12)
  );
''',
  '''
ALTER TABLE public.beacon_room_message_attachment
  ALTER COLUMN id SET DEFAULT concat(
    'A', substring(replace(gen_random_uuid()::text, '-', ''), 1, 12)
  );
''',
]);
