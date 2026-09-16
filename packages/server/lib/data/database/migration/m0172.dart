part of '_migrations.dart';

/// Issue #146 T10: drop temporary `beacon_can_read_linked_detail` alias.
final m0172 = Migration('0172', [
  r'''
DROP FUNCTION IF EXISTS public.beacon_get_can_read_linked_detail(public.beacon, json);
''',
  r'''
DROP FUNCTION IF EXISTS public.beacon_can_read_linked_detail(text, text);
''',
]);
