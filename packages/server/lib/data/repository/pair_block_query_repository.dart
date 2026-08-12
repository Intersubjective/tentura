import 'package:drift/drift.dart' show Variable;
import 'package:drift_postgres/drift_postgres.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/pair_block_query_port.dart';

import '../database/tentura_db.dart';

@Injectable(
  as: PairBlockQueryPort,
  env: [Environment.dev, Environment.prod],
  order: 1,
)
class PairBlockQueryRepository implements PairBlockQueryPort {
  const PairBlockQueryRepository(this._database);

  final TenturaDb _database;

  @override
  Future<Set<(String, String)>> blockedPairsAmong({
    required Set<String> userIds,
  }) async {
    if (userIds.length < 2) return const {};

    final ids = userIds.toList(growable: false);
    final rows = await _database
        .customSelect(
          r'''
SELECT
  CASE WHEN blocker_id < blocked_id THEN blocker_id ELSE blocked_id END AS a,
  CASE WHEN blocker_id < blocked_id THEN blocked_id ELSE blocker_id END AS b
FROM public.user_block
WHERE blocker_id = ANY($1::text[])
  AND blocked_id = ANY($1::text[])
''',
          variables: [
            Variable<List<String>>(ids, PgTypes.textArray),
          ],
          readsFrom: {_database.userBlocks},
        )
        .get();

    return {
      for (final row in rows)
        (row.read<String>('a'), row.read<String>('b')),
    };
  }
}
