part of '_migrations.dart';

/// Post-share email is independent of Request coordination. Existing email
/// subscribers receive the new default; an empty set (unsubscribe all) stays
/// empty. Stored Post relays use the same category as new dispatches.
final m0285 = Migration('0285', [
  '''
ALTER TABLE public.notification_preference
  ALTER COLUMN email_categories SET DEFAULT
    ARRAY['asksOfMe', 'connections', 'coordination', 'postsSharedWithMe']::text[];
''',
  '''
UPDATE public.notification_preference
SET email_categories = array_append(email_categories, 'postsSharedWithMe')
WHERE cardinality(email_categories) > 0
  AND NOT ('postsSharedWithMe' = ANY(email_categories));
''',
  '''
UPDATE public.notification_outbox receipt
SET category = 'postsSharedWithMe'
FROM public.beacon post
WHERE post.id = receipt.beacon_id AND post.kind = 1
  AND receipt.kind = 'newRelay' AND receipt.category = 'coordination';
''',
]);
