part of '_migrations.dart';

final m0107 = Migration('0107', [
  '''
DROP INDEX IF EXISTS public.invite_genealogy_ancestor_node_key;
''',
  '''
CREATE INDEX invite_genealogy_ancestor_node_key_children_page
  ON public.invite_genealogy (ancestor_node_key, descendant_user_created_at, descendant_node_key);
''',
]);
