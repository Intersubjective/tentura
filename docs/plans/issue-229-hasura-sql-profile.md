# Issue #229 — Hasura permission / computed-field SQL profile (spike tentura-z2iu.7)

Spike only: no production changes. Re-measures the operations that took 2–3 s before #231–#234.

## Method

1. Hasura (local container, admin secret) `POST /v1/graphql/explain` with `user` session `x-hasura-role: user`, `x-hasura-user-id: U6fca01549512` (the devcopy user with the most Requests). The generated SQL has the session variables already inlined, so it is stored verbatim as `issue-229-hasura-sql-profile/<operation>.sql`.
2. That SQL was run as `EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON)` on the local `tentura_devcopy` database (236 beacons), second (warm) run kept. Raw plans: `issue-229-hasura-sql-profile/<operation>.json`.
3. The queries are condensed versions of the client operations (`InboxFetch`, `MyWorkInit`, beacon by pk with `BeaconModel`, `FriendsFetch`) with the same permission-bearing fields; image/lineage/note sub-selections were dropped. For My Work the slower root field is stored.
4. "Worst node" = the plan node with the largest exclusive time (own time minus children, times loops).

## Results

"Rows" is the number of beacons (or friends) the operation returned, i.e. the loop count of the worst node. The aggregate result row Hasura returns for the root field is always 1.

| Operation | ms | Rows | Worst node | Proposed fix | Raw plan |
|---|---|---|---|---|---|
| Inbox | 55.76 | 14 beacons | `Result` under `SubPlan 5` (31.6 ms, 14 loops, ~2.3 ms/loop, 1869 buffer hits/loop): the per-beacon select list, which inlines `beacon_can_read_content` (twice), `beacon_can_read_involvement`, `beacon_access_level`, `beacon_access_reasons`, `beacon_get_is_pinned`, `beacon_get_my_vote` | The cost is the visibility chain `beacon_can_read_content` -> `person_are_mutually_visible_cached` (m0222 memo) re-evaluated per beacon and per computed field. Compute `can_read_content`/`access_level`/`access_reasons` once per row (one lateral call) and reuse; extend the m0222 per-transaction memo to the beacon-level result. | `issue-229-hasura-sql-profile/inbox.json` |
| My work | 29.70 | 8 beacons | `Result` under `SubPlan 5` (15.6 ms, 8 loops, ~1.95 ms/loop): same function set as Inbox | Same as Inbox. | `issue-229-hasura-sql-profile/my-work.json` |
| Beacon view | 11.32 | 1 beacon | `Result` under `SubPlan 5` (6.4 ms, 1 loop, 174 buffer hits): same function set; the same `beacon_can_read_content` also runs as the row filter on the `beacon` index scan | A single beacon already costs ~6 ms, so fix the function (`beacon_can_read_content` / `beacon_access_reasons`) rather than the plan shape: reuse the filter's result for the computed fields. | `issue-229-hasura-sql-profile/beacon-view.json` |
| People | 4.53 | 33 friends | `Result` under `SubPlan 4` (1.8 ms, 33 loops, ~0.06 ms/loop): the per-user select list calling `user_get_my_vote`, `user_get_trusts_viewer`, `user_get_is_mutual_friend` (plain `vote_user` lookups) | No fix needed; these are cheap indexed lookups. `SubPlan 5` (0.0 ms) only wraps `SubPlan 4`. | `issue-229-hasura-sql-profile/people.json` |

## How the function was identified

`EXPLAIN (VERBOSE, COSTS OFF)` of each stored `.sql` on `tentura_devcopy` prints the `Output:` of `SubPlan 5` (beacon operations) and `SubPlan 4` (people). Hasura's SQL computed-field wrappers (`beacon_get_can_read_content`, ...) are plain SQL functions that the planner inlines, so the plan shows `beacon_can_read_content(...)` directly. Function bodies were read from `pg_proc`; `beacon_can_read_content` calls `block_hides`, several `EXISTS` probes, and `person_are_mutually_visible_cached`, which is the function m0222 memoises per transaction. The per-node time is not split further by the plan (the function body is opaque to EXPLAIN), so which branch of `beacon_can_read_content` dominates is not measured here.

## Inbox

SQL: `issue-229-hasura-sql-profile/inbox.sql`. 55.76 ms for 14 beacons. No Seq Scan on `beacon` with a function filter and no hashed SubPlan appeared; the cost is `SubPlan 5` run once per inbox beacon (14 loops).

## My work

SQL: `issue-229-hasura-sql-profile/my-work.sql`. `authoredNonArchived` 29.7 ms (8 beacons), `helpOfferedNonArchived` 27.9 ms; both dominated by the same `SubPlan 5` function set.

## Beacon view

SQL: `issue-229-hasura-sql-profile/beacon-view.sql`. Single beacon: the one `SubPlan 5` evaluation is ~57% of execution time; planning (6.8 ms) is also significant.

## People

SQL: `issue-229-hasura-sql-profile/people.sql`. 33 friends; `SubPlan 4` runs per friend row and is cheap.

## Follow-up recommendations

- Memoise or share the `beacon_can_read_content` / `beacon_can_read_involvement` / `beacon_access_*` results per beacon within a request (the filter and the computed fields currently evaluate them independently).
- Re-measure on `tentura_perfsynth` (larger V) before deciding: devcopy has only 236 beacons, so per-row costs of ~2 ms scale linearly with inbox size.
- Planning time is 2–11 ms per operation (Hasura's SQL is large); consider fewer computed fields in list queries.
- No production change made in this bead.
