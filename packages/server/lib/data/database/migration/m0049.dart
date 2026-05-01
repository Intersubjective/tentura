part of '_migrations.dart';

final m0049 = Migration('0049', [
  '''
UPDATE public.beacon_commitment
  SET help_type = 'other'
  WHERE help_type = 'skill';
''',
]);
