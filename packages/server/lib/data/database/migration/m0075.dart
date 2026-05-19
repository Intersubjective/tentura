part of '_migrations.dart';

/// FCM token last refresh timestamp for ops and future idle eviction.
final m0075 = Migration('0075', [
  '''
ALTER TABLE public.fcm_token
  ADD COLUMN IF NOT EXISTS last_refreshed_at timestamp with time zone NOT NULL DEFAULT now();
''',
]);
