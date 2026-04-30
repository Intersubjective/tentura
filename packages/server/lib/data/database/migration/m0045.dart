part of '_migrations.dart';

/// Room message attachments: original filename for downloads / UI.
final m0045 = Migration('0045', [
  '''
ALTER TABLE public.beacon_room_message_attachment
  ADD COLUMN IF NOT EXISTS file_name text NOT NULL DEFAULT '';
''',
]);
