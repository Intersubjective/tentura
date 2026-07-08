part of '_migrations.dart';

/// Backfill + defaults for the `connections` notification category.
final m0111 = Migration('0111', [
  '''
ALTER TABLE public.notification_preference
  ALTER COLUMN push_categories
  SET DEFAULT ARRAY['asksOfMe','unblocksMe','coordination','connections'];
''',
  '''
ALTER TABLE public.notification_preference
  ALTER COLUMN email_categories
  SET DEFAULT ARRAY['asksOfMe','connections'];
''',
  '''
UPDATE public.notification_preference
SET push_categories = array_append(push_categories, 'connections')
WHERE NOT (push_categories @> ARRAY['connections']);
''',
  '''
UPDATE public.notification_preference
SET email_categories = array_append(email_categories, 'connections')
WHERE NOT (email_categories @> ARRAY['connections']);
''',
]);

