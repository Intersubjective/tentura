part of '_migrations.dart';

/// Per-user last-seen watermark for coordination item discussion threads.
final m0070 = Migration('0070', [
  '''
CREATE TABLE public.coordination_item_user_seen (
  user_id text NOT NULL REFERENCES public."user"(id),
  item_id text NOT NULL REFERENCES public.coordination_item(id) ON DELETE CASCADE,
  last_seen_at timestamptz NOT NULL,
  PRIMARY KEY (user_id, item_id)
);
''',
]);
