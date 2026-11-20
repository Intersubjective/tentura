# Forwarding flag cost in Inbox and My Work

- Database: `tentura_perfsynth`, restored from the local performance database
  into an isolated PostgreSQL 17.11 container on the same host. The source was
  at m0298. The restored copy had 14,245 beacons and was migrated through
  m0326 for the first comparison and through m0327 for the follow-up.
- Viewer ID: `U6fca01549512`, with session role `user`. Among viewers with
  both inbox items and authored Requests in the source, this viewer had the
  largest combined count (21 inbox items and 9 authored Requests before
  permission and archive filtering).
- Git SHA: `86e47c5f40e8df395fbed3511a84ef51f286b432` for the client operations,
  metadata, and m0326 schema. The follow-up also applied the m0327 migration
  accompanying this note.
- Measured 2026-11-20 on a local Intel Core i5-12600K. The restored cluster
  used the source's default JIT, work memory, and shared buffer settings.

## Method

Hasura v2.48.14 generated the SQL via `POST /v1/graphql/explain` using the
checked-out source metadata, the full client operations with imports expanded,
and the recorded viewer's session. Both operations used that viewer as
`userId`. My Work used `obligationBeaconIds: []`, the result of the client's
live-obligation lookup for that viewer. The remote schema was unnecessary
for these operations and was omitted from the isolated Hasura instance.

The same captured SQL ran against each function body using
`EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)`. For My Work, each sample sums
PostgreSQL's Execution Time for its four root statements, run in Hasura's
response order in the same transaction. Inbox uses its single statement's
Execution Time. These figures exclude planning and network time.

For replay, m0211 starts with `CREATE FUNCTION`. Use `CREATE OR REPLACE
FUNCTION` when loading it into the migrated benchmark database, where the
function already exists. Its argument list and SQL body are used verbatim.

Each block discarded three warm-up executions per operation and kept 12.
The two initial series reversed the order of the m0211 and m0318 bodies
(ABBA and BAAB). The follow-up ran four m0327 blocks with two interleaved
m0211 control blocks. The tables report the 48 samples per body and use
nearest-rank p95. The additional m0211 controls are in the
[warm samples](viewer-can-forward-m0318/warm-samples.csv), series 3.

## Inbox feed (`inbox_fetch.graphql`)

Hasura explain response: [InboxFetch JSON](viewer-can-forward-m0318/inbox-explain.json).
Measured SQL: [inbox_item](viewer-can-forward-m0318/inbox-inbox_item.sql).
The operation returned 14 rows for the measured viewer.

| Body | Warm runs | Median (ms) | p95 (ms) |
| --- | ---: | ---: | ---: |
| m0211 | 48 | 47.3630 | 52.1960 |
| m0318 | 48 | 52.4530 | 60.3210 |
| m0327 | 48 | 49.6380 | 58.0410 |

Verdict: slower

The m0318 median was 10.75% above m0211. With m0327 it was 4.80% above m0211.

## My Work (`my_work_fetch.graphql`)

Hasura explain response: [MyWorkInit JSON](viewer-can-forward-m0318/my-work-explain.json).
Measured SQL:

- [authoredNonArchived](viewer-can-forward-m0318/my-work-authoredNonArchived.sql)
- [helpOfferedNonArchived](viewer-can-forward-m0318/my-work-helpOfferedNonArchived.sql)
- `archivedIdHints`, whose SQL is in the raw explain response
- [obligationBeacons](viewer-can-forward-m0318/my-work-obligationBeacons.sql)

The four statements returned 8, 4, 1, and 0 rows respectively.

| Body | Warm runs | Median (ms) | p95 (ms) |
| --- | ---: | ---: | ---: |
| m0211 | 48 | 58.9155 | 63.3220 |
| m0318 | 48 | 62.6240 | 67.9560 |
| m0327 | 48 | 61.0520 | 66.3640 |

Verdict: not slower

The m0318 median was 6.29% above m0211. With m0327 it was 3.63% above m0211.

The Inbox result crossed the 10% median threshold. Migration m0327 removes
the `FROM (VALUES ...)` wrapper so PostgreSQL can inline
`beacon_get_viewer_can_forward`. A verbose plan with the Hasura session
literal showed the inlined expression in the scan output. The
function still applies the same status, forwarding policy, and involvement
checks, and both follow-up medians were within 10% of the m0211 medians.

## Parity

Parity viewers: `U6fca01549512`, `U92c5cd27ecd7`, `U63863d6c96cf`

This comparison ran in a read-only transaction on `tentura_perfsynth`
after m0327 was installed. It covered 42,735 beacon/viewer pairs.

```sql
SELECT count(*)
FROM public.beacon AS b
CROSS JOIN (VALUES ('U6fca01549512'), ('U92c5cd27ecd7'), ('U63863d6c96cf')) AS v(id)
WHERE public.beacon_get_viewer_can_forward(
  b, json_build_object('x-hasura-role', 'user', 'x-hasura-user-id', v.id)
) IS DISTINCT FROM COALESCE(
  b.status IN (0, 7, 8)
  AND (b.forward_policy = 1 OR b.user_id = v.id)
  AND public.beacon_can_read_involvement(b.id, v.id),
  false
);
```

Parity mismatches: 0
