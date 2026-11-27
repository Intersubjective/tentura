part of '_migrations.dart';

final m0345 = Migration('0345', [
  '''
CREATE TABLE public.user_privacy_setting (
  user_id text PRIMARY KEY REFERENCES public."user" (id) ON DELETE CASCADE,
  enabled boolean NOT NULL
)
''',
]);
