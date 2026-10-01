import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart' show Type, TypedValue;

import 'package:tentura_server/domain/port/trust_maintenance_sweep_port.dart';

import '../database/tentura_db.dart';

@Singleton(
  as: TrustMaintenanceSweepPort,
  env: [Environment.dev, Environment.prod, Environment.test],
  order: 1,
)
class TrustMaintenanceSweepRepository implements TrustMaintenanceSweepPort {
  const TrustMaintenanceSweepRepository(this._db);

  final TenturaDb _db;

  @override
  Future<List<(String subject, String object)>> projectNextBatch({
    required String afterSubject,
    required String afterObject,
    required int batchSize,
  }) =>
      _db.transaction(() async {
        final pairs = await _db
            .customSelect(
              r'''
SELECT subject_user_id AS s, object_user_id AS o
FROM (
  SELECT subject AS subject_user_id, object AS object_user_id
  FROM public.user_trust_edge
) AS pairs
WHERE (subject_user_id, object_user_id) > ($1, $2)
ORDER BY subject_user_id, object_user_id
LIMIT $3
''',
              variables: [
                Variable<String>(afterSubject),
                Variable<String>(afterObject),
                Variable(TypedValue(Type.integer, batchSize)),
              ],
            )
            .get();
        for (final pair in pairs) {
          await _db.customSelect(
            r'SELECT public.trust_project_pair($1, $2)',
            variables: [
              Variable<String>(pair.read<String>('s')),
              Variable<String>(pair.read<String>('o')),
            ],
          ).getSingle();
        }
        return [
          for (final pair in pairs)
            (pair.read<String>('s'), pair.read<String>('o')),
        ];
      });

  @override
  Future<void> bumpMrPublishEpoch() =>
      _db.customStatement('SELECT public.mr_bump_publish_epoch()');
}
