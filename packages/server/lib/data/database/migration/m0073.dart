part of '_migrations.dart';

/// Remove legacy self-ask rows (kind=ask, source=self_promise).
final m0073 = Migration('0073', [
  '''
DELETE FROM public.coordination_item
  WHERE kind = 2 AND source = 1;
''',
  '''
COMMENT ON COLUMN public.coordination_item.source IS
  '0=default (reserved)';
''',
]);
