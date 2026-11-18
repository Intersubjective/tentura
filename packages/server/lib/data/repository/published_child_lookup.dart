import 'package:drift_postgres/drift_postgres.dart' show PgTypes;

import '../database/tentura_db.dart';

Future<Map<String, String>> loadPublishedChildrenBySourceMessageId(
  TenturaDb database,
  List<String> sourceMessageIds,
) async {
  final rows = await database
      .customSelect(
        r'''
SELECT source_message_id, child_beacon_id
FROM public.beacon_promotions
WHERE source_message_id = ANY($1::text[])
  AND published_at IS NOT NULL
''',
        variables: [
          Variable<List<String>>(sourceMessageIds, PgTypes.textArray),
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
