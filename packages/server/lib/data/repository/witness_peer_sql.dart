/// One source for the witness-window peer query, shared by
/// `WitnessWindowRepository.rawWindowFacts` and the capability telemetry
/// (B086). MeritRank also scores non-person nodes (poll variants `V…`,
/// requests, comments); only people can be witnesses, so the join to
/// `"user"` keeps them out of the top-K before the LIMIT.
///
/// The arguments are SQL expressions (placeholders such as `$1` or a column
/// like `e.ego_id`), never user input.
String witnessPeerTopKSql({
  required String egoExpr,
  required String contextExpr,
  required String limitExpr,
}) =>
    '''
SELECT p.peer_id, p.forward_mr, p.viewer_explicitly_trusts_subject
FROM public.person_visibility_peers($egoExpr, $contextExpr) p
INNER JOIN public."user" u ON u.id = p.peer_id
WHERE p.forward_mr > 0
ORDER BY p.forward_mr DESC, p.peer_id ASC
LIMIT $limitExpr''';
