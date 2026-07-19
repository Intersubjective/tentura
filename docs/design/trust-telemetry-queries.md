# Trust telemetry queries (v1)

Structured logs from `ReviewFinalizationCase` emit one line per finalization from
`ForwardFinalizationDiagnostics` (eligible edges, rootless count, integrity failures,
per-sender Z, observed/unsuccessful pair counts). Use these SQL snippets against
`trust_evidence_event` for offline analysis. No public rankings.

## Events by context and source type

```sql
SELECT trust_context, source_type, count(*) AS n
FROM trust_evidence_event
WHERE applied_at > now() - interval '30 days'
GROUP BY 1, 2
ORDER BY 1, 2;
```

Including `negative_commitment_route_no_effect`:

```sql
SELECT date_trunc('day', applied_at) AS day, source_type, count(*)
FROM trust_evidence_event
WHERE trust_context = 'forward'
  AND source_type IN (
    'propagated_author_evaluated_commitment',
    'negative_commitment_route_no_effect',
    'unsuccessful_request_forward'
  )
GROUP BY 1, 2
ORDER BY 1, 2;
```

## Legacy contribution over time

```sql
SELECT date_trunc('week', applied_at) AS week, count(*)
FROM trust_evidence_event
WHERE trust_context = 'legacy'
GROUP BY 1
ORDER BY 1;
```

## Reuse rate of reinforced pairs

Pairs that received forward evidence more than once across requests:

```sql
SELECT subject_user_id, object_user_id, count(DISTINCT request_id) AS requests
FROM trust_evidence_event
WHERE trust_context = 'forward'
  AND source_type = 'propagated_author_evaluated_commitment'
GROUP BY 1, 2
HAVING count(DISTINCT request_id) > 1
ORDER BY requests DESC
LIMIT 100;
```

## Rootless-edge trend (S2 watch-metric)

Parse `forward_finalization_diagnostics` log lines or approximate from
`metadata` absence — v1 relies on structured logs for `rootlessEdgeCount`.

## Tombstone backlog

```sql
SELECT count(*) AS tombstones FROM meritrank_edge_tombstone;
```

## Stale effective projection detector

Pairs whose effective row is older than the newest source mutation:

```sql
SELECT e.subject, e.object, e.updated_at AS effective_updated,
       s.max_source_updated
FROM user_trust_edge e
JOIN (
  SELECT subject, object, max(updated_at) AS max_source_updated
  FROM user_trust_source_edge
  GROUP BY 1, 2
) s ON s.subject = e.subject AND s.object = e.object
WHERE e.updated_at < s.max_source_updated;
```
