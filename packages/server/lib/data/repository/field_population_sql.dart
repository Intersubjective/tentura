/// Uncapped Field population with the viewer at $1 and context at $2.
/// Consumers exclude blocked accounts when selecting from this population.
const fieldPopulationCtesSql = r'''
visible AS MATERIALIZED (
  SELECT unnest(public.person_visible_peer_ids_tx($1, $2)) AS id
), bond AS MATERIALIZED (
  SELECT peer_id AS id FROM public.person_bond_peers($1)
), temporary AS MATERIALIZED (
  SELECT peer_id AS id FROM public.person_temporary_forward_peers($1)
), population AS (
  SELECT id FROM visible UNION SELECT id FROM bond UNION SELECT id FROM temporary
  UNION SELECT object FROM public.vote_user WHERE subject = $1 AND amount > 0
  UNION SELECT $1
)
''';
