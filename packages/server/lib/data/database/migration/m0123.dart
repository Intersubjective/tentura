part of '_migrations.dart';

/// Default email digest on (daily) + coordination into email categories so
/// room @mentions are digest-eligible under default prefs.
final m0123 = Migration('0123', [
  '''
ALTER TABLE public.notification_preference
  ALTER COLUMN email_digest SET DEFAULT 'daily';
''',
  '''
ALTER TABLE public.notification_preference
  ALTER COLUMN email_categories
  SET DEFAULT ARRAY['asksOfMe','connections','coordination'];
''',
  '''
UPDATE public.notification_preference
SET email_digest = 'daily'
WHERE email_digest = 'off';
''',
  '''
UPDATE public.notification_preference
SET email_categories = array_append(email_categories, 'coordination')
WHERE NOT (email_categories @> ARRAY['coordination']);
''',
]);
