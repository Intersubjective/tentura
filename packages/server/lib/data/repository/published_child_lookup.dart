import 'package:drift_postgres/drift_postgres.dart' show PgTypes;

import '../database/tentura_db.dart';

/// Published children by source message. With [viewerUserId] a child the viewer
/// cannot read is left out: its id must not reach people outside its audience.
Future<Map<String, String>> loadPublishedChildrenBySourceMessageId(
  TenturaDb database,
  List<String> sourceMessageIds, {
  String? viewerUserId,
}) async {
  final rows = await database
      .customSelect(
        r'''
SELECT source_message_id, child_beacon_id
FROM public.beacon_promotions
WHERE source_message_id = ANY($1::text[])
  AND published_at IS NOT NULL
  AND ($2::text IS NULL OR public.beacon_can_read_content(child_beacon_id, $2))
''',
        variables: [
          Variable<List<String>>(sourceMessageIds, PgTypes.textArray),
          Variable<String>(viewerUserId),
        ],
      )
      .get();
  return {
    for (final row in rows)
      row.read<String>('source_message_id'): row.read<String>(
        'child_beacon_id',
      ),
  };
}
