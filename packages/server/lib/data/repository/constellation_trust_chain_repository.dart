import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/port/constellation_trust_chain_port.dart';

import '../database/tentura_db.dart';

@LazySingleton(
  as: ConstellationTrustChainPort,
  env: [Environment.dev, Environment.prod],
)
final class ConstellationTrustChainRepository
    implements ConstellationTrustChainPort {
  ConstellationTrustChainRepository(this._database);

  final TenturaDb _database;

  @override
  Future<List<ConstellationTrustChainPerson>> trustChain({
    required String viewerId,
    required String context,
    required String personId,
  }) async {
    // One statement keeps visibility, Field presence, blocks and the path in
    // the same snapshot. The visible set is materialized once for all hops.
    final rows = await _database
        .customSelect(
          r'''
WITH RECURSIVE visible AS MATERIALIZED (
  SELECT p.id
  FROM unnest(public.person_visible_peer_ids_tx($1, $2)) AS p(id)
  WHERE NOT public.block_hides($1, p.id)
), target AS MATERIALIZED (
  SELECT u.id FROM public."user" u
  WHERE u.id = $3 AND NOT public.block_hides($1, u.id)
    AND (
      u.id = $1
      OR EXISTS (SELECT 1 FROM visible v WHERE v.id = u.id)
      OR EXISTS (
        SELECT 1 FROM public.constellation_anchor a
        WHERE a.viewer_id = $1 AND a.person_id = u.id
          AND a.tombstone_at IS NULL
      )
      OR EXISTS (
        SELECT 1 FROM public.person_bond_peers($1) b WHERE b.peer_id = u.id
      )
      OR EXISTS (
        SELECT 1 FROM public.person_temporary_forward_peers($1) t
        WHERE t.peer_id = u.id
      )
    )
), walk(ids) AS (
  SELECT ARRAY[$1]::text[] FROM target
  UNION ALL
  SELECT w.ids || e.object
  FROM walk w
  JOIN public.user_trust_edge e ON e.subject = w.ids[cardinality(w.ids)]
  WHERE cardinality(w.ids) <= 4 AND e.target_w > 0
    AND w.ids[cardinality(w.ids)] <> $3
    AND NOT e.object = ANY(w.ids)
    AND (e.object = $3 OR EXISTS (
      SELECT 1 FROM visible v WHERE v.id = e.object
    ))
    AND NOT public.block_hides(e.subject, e.object)
), best AS (
  SELECT ids FROM walk WHERE ids[cardinality(ids)] = $3
  ORDER BY cardinality(ids), ids COLLATE "C"
  LIMIT 1
)
SELECT u.id, u.display_name
FROM best
CROSS JOIN LATERAL unnest(best.ids) WITH ORDINALITY AS p(id, position)
JOIN public."user" u ON u.id = p.id
ORDER BY p.position
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
        (
          userId: row.read<String>('id'),
          displayName: row.read<String>('display_name'),
        ),
    ];
  }
}
