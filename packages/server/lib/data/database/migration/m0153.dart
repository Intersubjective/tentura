part of '_migrations.dart';

/// Persists id-anchored text-mention ranges independently of legacy handles.
final m0153 = Migration('0153', [
  r'''
ALTER TABLE beacon_room_message
  ADD COLUMN mention_spans jsonb;
''',
]);
