part of '_migrations.dart';

/// Stop bumping `user_vsids.counter` on beacon / vote_beacon insert.
final m0074 = Migration('0074', [
  '''
DROP TRIGGER IF EXISTS public_vote_beacon_before_insert ON public.vote_beacon;
''',
  '''
DROP TRIGGER IF EXISTS public_beacon_before_insert ON public.beacon;
''',
  '''
DROP FUNCTION IF EXISTS public.vote_beacon_before_insert();
''',
  '''
DROP FUNCTION IF EXISTS public.beacon_before_insert();
''',
]);
