# Post participant counts: client follow-up and query plan

For **tentura-k65a.11**, carry the server participant `opened` flag through the
participant GraphQL fragment and mapper into `BeaconParticipant.opened`.
`PostParticipantsList._hasNotOpened` must use that flag instead of deriving it
from `lastSeenRoomAt`, preserving its author/viewer exclusions. The sheet and
`PostSummary.notOpenedCount` must agree for forwards, invites, messages and seen
rows. The sheet currently still uses `lastSeenRoomAt`; read cursors and unread
semantics must stay unchanged.

The complete repository `myPosts` SQL was checked with `EXPLAIN (ANALYZE,
BUFFERS, FORMAT JSON)` for a real Post author on a disposable clone of
`tentura_devcopy`, migrated to the current schema. The source database was not
modified, and the clone was dropped afterward. The query returned three Posts
in 6.850 ms. The materialized activity aggregate and each keyed activity source ran
three times (once per Post), not 57 times (the admitted peer rows across those
Posts). Joining peers rescanned the materialized activity rows without rerunning
the activity aggregate or its source scans. The JSON plan from this local check
is available at `/tmp/post_summary_grouped_full_plan.json` for this session.

Each source now uses the requested beacon-id array through `unnest` and a
lateral aggregate keyed to one beacon before grouping members. The unchanged
`request_list_batch_reads_pg_test.dart` passes its message-scan and subplan
budgets alongside the Post participant summary tests (33 tests total).

The complete `scripts/run_tests.sh server-pg` profile also passed after this
change, including the isolated PostgreSQL checks. No tests were weakened or
changed for the scan-budget fix.
