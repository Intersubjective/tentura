part of '_migrations.dart';

/// Opening a Request clears Field attention without reading its discussion.
/// Do not backfill from room cursors: those do not prove a Request was opened.
final m0295 = Migration('0295', [
  '''
CREATE TABLE public.beacon_field_seen (
    user_id text NOT NULL
      REFERENCES public."user"(id) ON DELETE CASCADE,
    beacon_id text NOT NULL
      REFERENCES public.beacon(id) ON DELETE CASCADE,
    PRIMARY KEY (user_id, beacon_id)
);
''',
]);
