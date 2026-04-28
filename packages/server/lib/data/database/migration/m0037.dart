part of '_migrations.dart';

/// Drops legacy public `comment` / `vote_comment` (replaced by beacon room
/// messages in m0036). CASCADE removes dependent MeritRank computed-field
/// functions that reference `public.comment`.
final m0037 = Migration('0037', [
  '''
DROP TABLE IF EXISTS public.vote_comment CASCADE;
''',
  '''
DROP TABLE IF EXISTS public.comment CASCADE;
''',
]);
