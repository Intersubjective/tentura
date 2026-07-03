part of '_migrations.dart';

/// Stores the authoring-time resolved address label for beacon locations.
final m0110 = Migration('0110', [
  '''
ALTER TABLE public.beacon
  ADD COLUMN IF NOT EXISTS address_label text;
''',
]);
