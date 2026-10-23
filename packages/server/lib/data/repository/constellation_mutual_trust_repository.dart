import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/constellation_field.dart';
import 'package:tentura_server/domain/port/constellation_mutual_trust_port.dart';

import '../database/tentura_db.dart';

@LazySingleton(
  as: ConstellationMutualTrustPort,
  env: [Environment.dev, Environment.prod],
)
final class ConstellationMutualTrustRepository
    implements ConstellationMutualTrustPort {
  ConstellationMutualTrustRepository(this._database);

  final TenturaDb _database;

  @override
  Future<List<ConstellationEdgeRecord>> explicitTrustEdgesOf({
    required String viewerId,
    required String context,
    required String personId,
  }) async {
    if (viewerId.trim().isEmpty || personId.trim().isEmpty) {
      return const [];
    }
    // The candidates are the people the person trusts both ways, a short
    // list bounded by their own trust marks. The field's edge function then
    // decides, as for the field itself, which of them and which of their
    // edges the viewer may see.
    final rows = await _database
        .customSelect(
          r'''
WITH partners AS (
  SELECT vu.object AS id
  FROM public.vote_user vu
  WHERE vu.subject = $3 AND vu.amount > 0
  INTERSECT
  SELECT vu.subject
  FROM public.vote_user vu
  WHERE vu.object = $3 AND vu.amount > 0
)
SELECT e.src, e.dst
FROM public.constellation_trust_edges(
  $1,
  $2,
  ARRAY(SELECT $3::text UNION SELECT p.id FROM partners p)
) e
WHERE e.tier = 1 AND (e.src = $3 OR e.dst = $3)
ORDER BY e.src, e.dst
''',
          variables: [
            Variable.withString(viewerId),
            Variable.withString(context),
            Variable.withString(personId),
          ],
        )
        .get();
    return [
      for (final row in rows)
        ConstellationEdgeRecord(
          src: row.read<String>('src'),
          dst: row.read<String>('dst'),
          tier: 1,
        ),
    ];
  }
}
