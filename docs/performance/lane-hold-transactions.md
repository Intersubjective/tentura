# Measuring transaction lane holds

The measurement runner freezes the unmodified commit and the current server
sources in separate directories. It runs the same seven production workloads
serially on a dedicated perf database, using the existing PostgreSQL fixtures.
It does not change HEAD, create commits, or publish a PR.

```bash
# Connect to the local admin database using the standard POSTGRES_* settings.
# Clone a perf DB first; never benchmark tentura_devcopy or perfsynth directly.
PGPASSWORD="${POSTGRES_PASSWORD:-password}" psql \
  --host="${POSTGRES_HOST:-127.0.0.1}" --port="${POSTGRES_PORT:-5432}" \
  --username="${POSTGRES_USERNAME:-postgres}" --dbname=postgres \
  --command='CREATE DATABASE tentura_test_lane_hold_perf TEMPLATE tentura_devcopy;'
export TENTURA_LANE_HOLD_PERF_DB=tentura_test_lane_hold_perf
python3 scripts/perf/measure_lane_hold.py --before <unmodified-commit>
```

Use a new clone of `tentura_devcopy` or `perfsynth`. If PostgreSQL refuses a
template clone because the source has active connections, clone with
`pg_dump`/`pg_restore` instead; do not terminate connections on the original.
The runner migrates the clone and installs pgmer2. PostgreSQL and the real
MeritRank service must be available. Retained samples are never dropped. Run
without other sweeps or benchmarks competing for the shared MeritRank service.

Each actual BEGIN and awaited COMMIT is bracketed by PostgreSQL
`clock_timestamp()` queries on the workload connection. The same two clock
round trips apply to both phases. Seeding, fixture cleanup, and acknowledgement
sync after COMMIT are excluded. Samples are retained in
`tentura_perf.lane_hold_samples` and the report reads their durations back from
PostgreSQL.

The baseline must complete every fixture's row assertions. Only its final,
new transaction-budget assertions may fail: those violations are precisely
what is being measured. The after phase must pass every assertion. A report is
written only after every measured worst lane hold improves.

The report's revision fields are SHA-1 fingerprints of the frozen source trees,
including the identical generated outputs reused in both phases. They describe
the uncommitted implementation accurately; `beforeBaseCommit` records the git
baseline. Source snapshots and the two intermediate reports remain in the
reported directory under `/tmp` for inspection.

The runner writes `lane-hold-transactions.json` and a PR-ready measurement table
in `lane-hold-transactions-pr.md`. Pass `--pr-url <existing-pr-url>` to also write
the prepared PR JSON artifact. Alloy can publish the table when it handles git
and the PR; the artifact explicitly records its prepared status.

Copy the generated before/after table here and into the PR. Recorded performance
evidence is documentation, not a test gate. Keep the behavioural transaction
budget tests, including the acknowledgement test that blocks `mr_sync()` and
checks that another database operation can finish after the writes commit.

## Measurement status (2026-10-12)

Measured by `scripts/perf/measure_lane_hold.py --before 29f327e2d` on the
local perf DB clone `tentura_test_lane_hold_perf` of `tentura_devcopy`.
Samples: `docs/performance/lane-hold-transactions.json`.

Measured on perf DB `tentura_test_lane_hold_perf`. Samples: `docs/performance/lane-hold-transactions.json`. Source SHA-1 before `df3a45d54108938fda423293056af204630b436c`, after `7ef23a5d704ef2897e87475f7360dcd555f5bc52` (frozen source trees, not new commits).

| Path | Rows | Before worst lane hold (ms) | After worst lane hold (ms) |
| --- | --- | --- | --- |
| trust_publish_ack | 200 | 1007.75 | 29.399 |
| attention_capture | 1201 | 432.076 | 47.001 |
| attention_apply | 200 | 63.614 | 29.152 |
| attention_undo | 1201 | 3112.124 | 44.576 |
| user_erasure_published | 1201 | 5569.405 | 1682.228 |
| user_erasure_drafts | 1201 | 2213.326 | 173.879 |
| contact_resolution | 200 | 1496.415 | 1422.579 |
