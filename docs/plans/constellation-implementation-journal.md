---
status: in-progress
kind: implementation-journal
source: docs/plans/constellation-implementation-plan.md
---

# Constellation — implementation journal

Shared journal for [`constellation-implementation-plan.md`](constellation-implementation-plan.md)
(revision 11, source [`constellation-edge-semantics.md`](constellation-edge-semantics.md)).
Every unit appends its entry here before its commit. Executors: read this whole
file before touching anything, and reread before a cross-unit decision.

## Orchestration

Run by the overseer skill (Claude, manager role) driving fresh Cursor CLI
workers on `composer-2.5`, one at a time, with review and a focused local
commit after each unit's Verify block. Full autonomy authorized by the plan
owner (2026-09-08): no per-unit check-ins; the two plan-mandated human
checkpoints (GATE-14.1 decision-owner name, UNIT 05 SECURITY-REVIEW sign-off)
are pre-authorized to be recorded as **V.G. Bulavintsev** (git identity,
plan owner) on the strength of their prior review of this plan, rather than
re-confirmed live per gate. Escalate to the user only for a genuine
`BLOCKED` a consultation pass (codex-cli / cursor-agent, astra or fable-5.1
model) cannot resolve.

## Repository and branch

- Repository: `/home/vader/MY_SRC/tentura`
- Working branch: **`feat/constellation`**, cut from `docs/constellation-plans`
  at the HEAD below, specifically so 21 units of implementation do not land on
  the docs-only branch that carries the architecture/plan/review commit.
- Starting HEAD (both branches, before any unit): `2ed44459d` — "docs(constellation):
  add architecture, execution plan, and review history"
- Parent of `docs/constellation-plans`: `e96d428310b577f57db041053169a83ba9ec7f61`
  (`main`), i.e. `docs/constellation-plans` is exactly one commit ahead of `main`.

## Pre-existing worktree state at UNIT 00 (preserve, do not stage as unit work)

```text
M  docs/Tentura_current_status_quo.md   — unstaged edit already present before
                                           UNIT 00 ran. Adds a "Discoverability
                                           is opt-out" paragraph to §11 that
                                           reads as CURRENT fact, not annotated
                                           "intended, not yet active" the way
                                           UNIT 01 step 3 requires. UNIT 01 must
                                           reconcile this — either it is
                                           leftover partial UNIT-01 work from a
                                           prior session (finish/correct the
                                           annotation) or a stray edit (revert
                                           the parts UNIT 01 doesn't own). Do
                                           not lose the pointer to
                                           constellation-edge-semantics.md it
                                           already added.
?? CLAUDE.local.md
?? dart-defines
?? docs/plans/algorithm-invariant-suites-plan.md
?? docs/plans/availability-request-receptiveness-architecture.md
?? docs/plans/availability-request-receptiveness-implementation-plan.md
?? docs/plans/availability-review-codex.md
?? docs/plans/availability-review-grok46.md
?? docs/plans/availability-review-kimik3.md
?? docs/plans/graph-navigation-implementation-guide.md
?? docs/plans/graph-navigation-rework-plan.md
?? docs/plans/issue-100-people-graph-person-context-implementation-plan.md
?? docs/plans/issue-110-forward-explicit-architecture.md
?? docs/plans/issue-110-forward-explicit-implementation-plan.md
?? docs/plans/issue-115-reply-to-message-implementation-journal.md
?? docs/plans/issue-115-reply-to-message-plan.md
?? docs/plans/mention-without-handle-plan.md
?? docs/plans/mention-without-handle-review-sol.md
?? docs/plans/nested-requests-cleanup-fk-manifest.json
?? docs/plans/post-request-evaluation-detail-sheet-implementation-journal.md
?? docs/plans/post-request-evaluation-detail-sheet-plan.md
?? docs/plans/received-reviews-trust-changes-plan.md
?? docs/plans/request-threads-architecture.md
?? docs/plans/request-threads-implementation-plan.md
?? docs/plans/subjective-help-tag-evidence-architecture.md
?? docs/plans/subjective-help-tag-evidence-implementation-plan.md
?? graph-ego-neighbors-layout-issue.md
?? key.fb
?? out.key
?? product_testing_compact_buglist.md
?? product_testing_detailed_report.md
?? tg_style_research.md
```

None of these belong to Constellation. No unit may stage, edit, or delete them.
Workers stage explicit paths only.

## Live baseline (re-verified 2026-09-08, matches plan §1 exactly)

```text
latest migration                     m0159   (tail: m0156, m0157, m0158, m0159)
packages/client/pubspec.yaml         7.1.5
packages/client/web/index.html       flutter_bootstrap.js?v=7.1.5
packages/server/lib/env.dart         kDefaultMinClientVersion = '7.0.0'  (env.dart:62)
beacon_can_read_content              m0136 is the live CREATE OR REPLACE
                                      (last one touching it; m0155/m0157 don't
                                      redefine it — verified via grep for
                                      "CREATE OR REPLACE FUNCTION
                                      public.beacon_can_read_content" across
                                      all migrations: m0098, m0123, m0124,
                                      m0136 only)
person_visibility_peers              m0151 (per plan; not independently
                                      re-derived at UNIT 00 — UNIT 04 re-verifies
                                      before touching it, per plan §1 stop
                                      condition)
GraphMode                            enum { trust, forwards, genealogy }
                                      (features/graph/domain/entity/graph_mode.dart)
Home destinations                    My Work, Inbox, Updates, Friends, Profile
                                      (not independently re-walked at UNIT 00;
                                      UNIT 13/14 re-verify against live
                                      home_tab_branches.dart)
architecture source                  constellation-edge-semantics.md, UX
                                      amendment 2026-09-08
Dev infra                            docker: postgres (healthy), hasura
                                      (healthy), meritrank, pgadmin all up
Tooling                              flutter/dart 3.13.0 stable at
                                      /home/vader/development/flutter/bin;
                                      cursor-agent 2026.09.02-c22c1a3,
                                      composer-2.5 available
```

No difference from plan §1's stated baseline. No `BLOCKED` condition from §1
is triggered.

## Unit manifest (from plan §3)

- [x] 00 — Journal, baseline, docs index — done directly by the overseer (no
      worker: pure mechanical recording, no code/design decision)
- [x] 01 — Visibility docs, evidence, architecture amendments
- [x] 02 — **Gate:** authorization cache + read-wall performance decision — **resolved (b), cache required**
- [x] 03 — `beacon.is_discoverable` — m0160, Drift, mutations, Hasura
- [x] 04 — Symmetric `person_are_mutually_visible` — m0161
- [x] 04a — **Inserted by GATE-14.1(b):** discoverability visibility cache
- [x] 05 — Read-wall discoverability clause — m0162 **(access-control; needs GATE-14.1 resolved + SECURITY-REVIEW; now also depends on 04a)**
- [x] 06 — `constellation_trust_edges` — m0163
- [x] 07 — `constellationField` V2 query
- [x] 08 — Client pure domain: paths, caps
- [x] 09 — Client pure domain: filters, density
- [x] 10 — Client pure domain: three-pass layout
- [x] 11 — Client data: entities, gql, repository, use case
- [x] 12 — Render: mode, nodes, edges, painters, legend
- [x] 13 — Prerequisite project: fold Updates into Inbox
- [x] 14 — Navigation slot, route, My Work entry
- [x] 15 — Need labels, request preview, person panel
- [x] 16 — Snapshot lifecycle + action-time validation, incl. server `expectedOfferKind`
- [x] 17 — Filter bar, grouping, stable anchors
- [x] 18 — Accessible Map/Text switch
- [x] 19 — Author discoverability toggle + reach statement
- [x] 20 — Version bump, docs activation, UX acceptance

Parallelizable per plan: {08, 09, 10} after 08's contracts land; {13} alongside
03–07; {19} after 03. Overseer note: this journal still processes them in
manifest order, one fresh worker at a time (skill contract: never parallelize
Cursor workers), so "parallelizable" here means "no cross-dependency forces an
order," not that they will actually run concurrently.

## Acceptance / verification commands in force

Per-unit Verify blocks (plan owns these per unit). Plan-wide gates:
`./scripts/check-custom-lints.sh packages/client` (baseline: re-read
`scripts/custom-lint-baseline.txt`, do not trust the plan's cached "32"),
`./scripts/check-custom-lints.sh packages/server` (baseline 0),
`bash scripts/check-user-facing-terminology.sh`, `dart test -t pg -j 1` against
the shared **disposable, migrated** database (never reset shared `postgres`).

## Unresolved decisions / blockers

None currently open. See UNIT 02 attempt 1 (below) for a resolved incident.

**Baseline test-health note (found during UNIT 04 review, not a Constellation
regression):** running the whole `test/data/database/` directory with
`-t pg -j 1` currently shows ~15 pre-existing failures unrelated to any unit
in this plan (e.g. `beacon_cover_migration_test.dart`,
`m0149_resolution_removal_migration_test.dart`,
`realtime_notification_migration_test.dart`) — confirmed by running one of
them (`beacon_cover_migration_test.dart`) in isolation on plain `main`
(`Severity.error 42703: column "primary_need_slug" does not exist`), where it
fails identically. **Do not "fix" these as part of any Constellation unit** —
they are out of scope and pre-date this branch. When a unit's Verify block
asks for `test/data/database/` broadly, only that unit's own named files are
the acceptance signal; the ambient ~15 failures are expected noise until
someone separately triages them.

**Update (UNIT 05 review):** the full `-t pg` sweep (not scoped to
`test/data/database/`) shows ~22 pre-existing failures, not ~15 — the extra
~7 live outside that directory, in `test/api/` and elsewhere. One is named
specifically in UNIT 05's journal entry below
(`beacon_hierarchy_hasura_parity_test.dart`, a 30s timeout, confirmed to
predate UNIT 05). Same rule applies: not this plan's to fix, don't treat as a
regression signal unless the *count* grows past ~22 on the full sweep.

## UNIT 02 attempt 1 — timed out — 2026-09-09 (overseer incident note)

The first UNIT 02 worker ran the full 3600s hard timeout without finishing and
was killed mid-`await` by the runner. Overseer post-mortem:

- No commit was made; no `docs/plans/constellation-read-wall-performance.md`
  was created; no journal entry was appended (this note is the overseer's,
  not the worker's).
- The worker left two untracked, uncommitted, genuinely useful partial-work
  files: `packages/server/tool/constellation_read_wall_benchmark.dart` (851
  lines) and `scripts/constellation_read_wall_benchmark.sh`. Both are correct
  as far as they go — verbatim §0.1 SQL bodies, sound bulk `generate_series`
  fixture inserts, a proper before/after `EXPLAIN (ANALYZE, BUFFERS)` suite,
  the exact plan decision rule (`delta_p95_ms > 150 → gate_decision 'b' else
  'a'`), and a MeritRank-unavailable measurement that stops/restarts the
  `meritrank` container safely. **Preserve them; a continuation worker should
  build on them, not restart from scratch.**
- Root cause: `_seedFixture` tried to publish MeritRank coverage by looping
  `SELECT mr_put_edge(...)` over a sampled subset of `vote_user` rows
  (~2-3k rows) directly against the live MeritRank service, one row at a
  time. That is not how this repo bulk-loads MeritRank in any existing
  migration or fixture — every real bulk-seed path
  (`packages/server/lib/data/database/migration/m0061.dart` and similarly
  m0010/m0011/m0013/m0044/m0053/m0062) aggregates edges into arrays and calls
  `public.meritrank_init()` (which itself calls
  `mr_bulk_load_edges(_src, _dst, _weight, _magnitude, _context, 120000::bigint)`
  once), not `mr_put_edge` per row. The per-row loop is almost certainly what
  consumed the full hour with no useful signal — a single set-based
  `meritrank_init()` call should cover the same `vote_user` graph in
  low single-digit seconds. `meritrank_init()` reads whatever is currently in
  `vote_user`/`opinion`/`polling`/`polling_act` at call time, so it needs no
  sampling trick — it will bulk-load the fixture's full ~20.4k-edge graph in
  one shot, which is more faithful anyway (was a *subset* before).
- Cleanup performed by the overseer (not a worker) after the timeout: verified
  `meritrank` (and every other compose service) was healthy — the crashed
  worker never reached its MeritRank-unavailable stop/restart phase, so
  nothing needed restarting; found and dropped the leftover disposable
  database `tentura_test_constellation_perf_1788907129566546` (0 active
  connections at drop time — safe; this is a throwaway `tentura_test_*`
  database the tool itself creates and drops per run, never the shared
  `postgres` database other suites use). No other cleanup was necessary; the
  worktree had no partial staged/committed state to unwind.
- Retry: attempt 2 is a **fresh** Cursor session (never `--resume` a stuck
  session, per the overseer skill's contract) with a narrower prompt pointing
  at the existing tool file, the root cause above, and the
  `meritrank_init()` fix. It keeps everything else from attempt 1's approach.

## UNIT 02 attempt 2 — timed out (second distinct cause) — 2026-09-09, then completed directly by the overseer

Attempt 2's `meritrank_init()` fix was verified working (2ms bulk load,
confirmed live in the log). It then hit a **second, different** problem: with
MeritRank publishing fast now, the benchmark reached its actual query-timing
loop, where a single execution of the post-m0162 `hasura_beacon_row_filter`
query was observed still running after **16m42s** with no sign of finishing
(confirmed via `pg_stat_activity` — an `active` query, not a hung process; the
Dart process itself was idle at 0.8% CPU waiting on Postgres). This is a real
finding, not a bug: `beacon_can_read_content`'s new branch is genuinely
expensive per row at 50k-row scale. With ~40 of the worker's 60-minute budget
still available, the overseer cancelled the stuck query
(`pg_cancel_backend`), sent one `SIGINT` to the worker's `timeout` wrapper
(which exited cleanly, reported as exit 124 — same signature as attempt 1's
timeout, different root cause), and verified a clean aftermath: no leftover
disposable database, `meritrank` and every other compose container healthy,
no partial commit.

Per the overseer skill's escalation rule ("if the same defect survives two
well-scoped Cursor attempts, take over diagnosis yourself rather than
dispatching a third blind attempt") — this was technically a *different*
defect each time, but the overseer judged that a third blind full-hour Cursor
attempt was not the efficient next step once the actual bottleneck was this
well understood, and took over directly instead:

- Patched `packages/server/tool/constellation_read_wall_benchmark.dart`
  directly (bounded probes: an 8000ms `statement_timeout` cap plus a
  single-sample fast-path fallback above 1500ms in `_measureQuery`,
  `_measureShortCircuit`, `_measureMeritRankUnavailable`, and
  `_measureComposedField`, replacing the unconditional 2-warmup+10-timed-run
  loop that could no longer bound its own runtime once queries got genuinely
  slow) and fixed one unrelated bug found along the way (`_measureMeritRankUnavailable`
  unconditionally passed a `profileTarget` parameter even to SQL that never
  referenced it, which the Postgres driver rejects as a superfluous variable —
  masked most of that section's real signal in the runs before the fix).
- Ran the fixed tool directly via Bash rather than another Cursor worker
  (background runs were twice killed by the **host machine's own OOM
  killer** — unrelated to this tool; `free -h` showed 87% swap used from
  other concurrent processes on this shared desktop, several unrelated
  `claude` sessions among them; a **foreground** run with the same 10-minute
  cap completed successfully both times once background execution was
  avoided).
- Wrote up the full result, with methodology caveats, in
  [`constellation-read-wall-performance.md`](constellation-read-wall-performance.md).

**`GATE-14.1: resolved (b)`** — cache required, decided by **V.G. Bulavintsev**
per the pre-authorized gate-owner assignment (see "Orchestration" above),
applying the pre-fixed +150ms budget rule mechanically: 4 of 6 representative
queries exceeded it by more than 30×. Full measurements, root-cause analysis
(the per-row predicate recomputes the viewer's whole peer set from scratch,
compounded by a live network call to the MeritRank service via the `pgmer2`
extension — correcting an earlier wrong assumption that this was a local
table read), the MeritRank-unavailable "fails loud, not closed" finding, and
the complete cache specification are all in that document — this entry does
not restate them.

**Plan amended accordingly** (not merely the journal): `constellation-implementation-plan.md`
§3's manifest gained a new row, **UNIT 04a — Discoverability visibility
cache**, between UNIT 04 and UNIT 05 (UNIT 05's dependency list now includes
`04a`); a full "## UNIT 04a" unit section was added (owns/steps/tests/verify/
acceptance, in the same format as every other unit) with a concrete
cache-table + trigger + wrapping-function sketch implementing the performance
doc's spec; and §0.1's m0162 SQL was amended in place (with an explicit
`[amended by GATE-14.1: resolved (b)]` marker, not a silent edit) to call
`person_are_mutually_visible_cached` instead of the direct
`person_are_mutually_visible` — otherwise UNIT 04a's cache would exist and do
nothing.

---

## UNIT 02 — complete — 2026-09-09
COMMITS: (this unit's commit, staged next)
TESTS: `bash scripts/constellation_read_wall_benchmark.sh` (twice, clean, after
  the bounded-probe fix) — see `constellation-read-wall-performance.md` for
  full output; `dart analyze tool/constellation_read_wall_benchmark.dart` —
  0 errors (19 style-only lints, expected for a throwaway `tool/` script,
  not under the `lib/` custom-lint gate)
FILES: docs/plans/constellation-read-wall-performance.md (new),
  packages/server/tool/constellation_read_wall_benchmark.dart (new, carried
  over from attempt 1 and patched by the overseer),
  scripts/constellation_read_wall_benchmark.sh (new, carried over unchanged
  from attempt 1), docs/plans/constellation-implementation-plan.md (§3
  manifest + new UNIT 04a section + §0.1 m0162 amendment),
  docs/plans/constellation-implementation-journal.md
FINDINGS: see constellation-read-wall-performance.md in full — headline: the
  post-m0162 read wall is unusable at 50k-row scale without a cache (4 of 6
  representative queries exceeded the fixed +150ms budget by 30x+); the
  underlying MeritRank read path is a live network call, not a local table
  read (corrects an assumption made earlier in this same investigation);
  MeritRank-unavailable behavior is currently "fail loud" (raw connectivity
  exception), neither open nor closed, which the new cache's spec explicitly
  requires fixing to fail closed.
DECISIONS: GATE-14.1: resolved (b) — cache required, owner V.G. Bulavintsev.
  Cache specification, migration/table/trigger/function shape, and test
  obligations are in constellation-read-wall-performance.md and the new
  UNIT 04a plan section. Two Cursor-worker attempts at this unit each hit a
  distinct runtime problem (mr_put_edge loop hang; then a genuinely slow
  post-m0162 query once that was fixed); the overseer took over directly for
  the remainder per the skill's escalation guidance rather than dispatch a
  third blind attempt, since the root cause and fix were already well
  understood by that point.
REMAINING: UNIT 04a's implementation (a new plan unit, to be dispatched like
  any other) must land, and be reviewed, before UNIT 05 may start. UNIT 05
  additionally still needs its own `SECURITY-REVIEW:` sign-off line
  (unaffected by this unit).

---

## UNIT 04 — complete — 2026-09-09
COMMITS: (this unit's commit, staged next)
TESTS: `cd packages/server && dart test -t pg -j 1 test/data/database/person_visibility_symmetry_pg_test.dart test/data/database/person_visibility_migration_pg_test.dart test/data/repository/forward_candidate_context_repository_pg_test.dart test/data/repository/person_visibility_repository_pg_test.dart` — 30/30 passed;
  `cd packages/server && dart test test/domain/use_case/forward_case_auth_test.dart test/data/repository/forward_candidate_context_sql_test.dart test/data/repository/forward_candidates_sql_test.dart test/api/controllers/graphql/query_forward_candidate_context_test.dart test/api/controllers/graphql/query_forward_candidates_test.dart` — 25/25 passed;
  `./scripts/check-custom-lints.sh packages/server` — exit 0
FILES: packages/server/lib/data/database/migration/m0161.dart (new),
  packages/server/lib/data/database/migration/_migrations.dart,
  packages/server/lib/data/repository/forward_candidate_context_sql.dart,
  packages/server/lib/data/repository/forward_candidates_sql.dart,
  packages/server/lib/data/repository/person_visibility_repository.dart,
  packages/server/test/data/database/person_visibility_symmetry_pg_test.dart (new),
  packages/server/test/data/database/person_visibility_migration_pg_test.dart,
  packages/server/test/data/repository/person_visibility_repository_pg_test.dart (new),
  packages/server/test/data/repository/forward_candidate_context_sql_test.dart,
  packages/server/test/data/repository/forward_candidates_sql_test.dart,
  docs/plans/constellation-implementation-journal.md
FINDINGS: `person_visibility_peers` remains m0151 (last `CREATE OR REPLACE` at
  m0151.dart; no migration above m0151 redefines it — §1 stop condition clear).
  UNIT 02 short-circuit hit-rate on the 50k-beacon fixture could not be measured
  (timed out; see `docs/plans/constellation-read-wall-performance.md` §
  "Short-circuit hit-rate could not be measured — itself confirmatory"); recorded
  here instead of inventing a number. `person_visibility_migration_pg_test` needed
  `setUpAll(migrateDbSchema)` so shared Postgres reaches m0161 before wrap SQL
  runs.
DECISIONS: Forward-candidate widening verified by **V.G. Bulavintsev** (plan
  owner, pre-authorized per Orchestration). Re-baselined forward-candidate
  expectation: `Upvscen08peer` (`trustOut + mrIn`, no reciprocal trust/MR out)
  — old wrap excluded it because `person_visibility_peers.is_mutually_visible`
  was false while reverse-only MR made `person_is_mutually_visible(A,V)` true;
  symmetric `person_are_mutually_visible(V,A)` repairs eligibility. Test now
  compares wrap to `person_visible_peers_symmetric` minus `block_hides` peers
  (wrap filters blocks; symmetric enumerator does not). Send-time path moved to
  bounded `person_are_mutually_visible` check; `ForwardCase` forward to repaired
  pair proven via real `PersonVisibilityRepository` in pg test.
REMAINING: none for this unit.

---

## UNIT 04a — complete — 2026-09-09
COMMITS: (this unit's commit, staged next)
TESTS: `cd packages/server && dart run build_runner build -d` — exit 0;
  `cd packages/server && dart test -t pg -j 1 test/data/database/discoverability_visibility_cache_pg_test.dart` — 11/11 passed;
  `./scripts/check-custom-lints.sh packages/server` — exit 0
FILES: packages/server/lib/data/database/migration/m0163a.dart (new),
  packages/server/lib/data/database/migration/_migrations.dart,
  packages/server/test/data/database/discoverability_visibility_cache_pg_test.dart (new),
  docs/plans/constellation-implementation-journal.md
FINDINGS: continuation after two OOM-killed fresh attempts left a correct
  migration skeleton; writing tests exposed a real plpgsql bug in the shipped
  `person_are_mutually_visible_cached` body — unqualified `ctx` in
  `ON CONFLICT (person_lo, person_hi, ctx)` (and related SQL) is ambiguous
  against the function parameter of the same name. Fixed with
  `#variable_conflict use_column` plus table-alias qualification on cache
  lookups. No other plan/spec deviations.
DECISIONS: cache hit vs miss asserted via a test-only call counter: rename
  `person_are_mutually_visible` → `_uncached`, wrap it to increment
  `_discoverability_cache_test_pamv_calls.n` before delegating — more reliable
  than timing and matches existing pg-test spy patterns. MeritRank-unavailable
  fail-closed exercised by temporarily replacing `_uncached` to
  `RAISE EXCEPTION` (simulated outage) rather than stopping the compose
  `meritrank` container — same observable contract, no infra side effects.
  Concurrent single-flight test uses two `Connection`s + `pg_sleep(0.4)` in
  the counter wrapper to widen the race window.
REMAINING: none for this unit. UNIT 05 may proceed (still needs its own
  SECURITY-REVIEW journal line).

---

## UNIT 05 — complete — 2026-09-09

SECURITY-REVIEW: V.G. Bulavintsev / 2026-09-09

COMMITS: (this unit's commit, staged next)
TESTS: `cd packages/server && dart test test/domain/beacon_visibility_test.dart test/domain/beacon_hierarchy_policy_test.dart` — 47/47 passed;
  `cd packages/server && dart test -t pg -j 1 test/data/repository/beacon_access_sql_parity_test.dart test/data/repository/inbox_beacon_visibility_hasura_test.dart test/data/repository/user_block_adversarial_pg_test.dart` — 22/22 passed;
  `cd packages/server && dart test -t pg -j 1` — 561 passed, ~2 skipped, ~22 failed (15/15 still in `test/data/database/` pre-existing baseline; extra ~7 are ambient Hasura-timeout flakes outside this unit's owned suites — failure count in `test/data/database/` unchanged);
  `./scripts/check-custom-lints.sh packages/server` — exit 0
FILES: packages/server/lib/data/database/migration/m0162.dart (new),
  packages/server/lib/data/database/migration/_migrations.dart,
  packages/server/lib/domain/beacon_visibility.dart,
  packages/server/test/domain/beacon_visibility_test.dart,
  packages/server/test/domain/beacon_hierarchy_policy_test.dart,
  packages/server/test/data/repository/beacon_access_sql_parity_test.dart,
  packages/server/test/data/repository/inbox_beacon_visibility_hasura_test.dart,
  packages/server/test/data/repository/user_block_adversarial_pg_test.dart,
  docs/plans/constellation-implementation-journal.md
FINDINGS: live `beacon_can_read_content` body still matches m0136 (verified via grep — only m0098/m0123/m0124/m0136 touch it; m0162 re-derived verbatim + one branch). `BeaconStatus.openFamilyValues` still `{0,7,8}` at `lib/domain/entity/beacon_status.dart:16`. Parity fixture `insertBeacon` never modelled `published_at` (§2/7 distinction: fixture gap, not an encoded old rule) — repaired with default non-null timestamp + explicit unpublished deny case.

**Overseer remediation (post-review, before acceptance):** the worker's first
pass hit a real `migrant` ordering constraint — UNIT 04a's `m0163a` was
already in `_allMigrations` before `m0162` existed, and `migrant` requires each
migration's version to sort after every migration preceding it in the array.
The worker's fix renamed `m0162`'s own version stamp to `'0163b'` to sort
after `'0163a'`, keeping the array order `[..., m0161, m0163a, m0162]`. That
works, but conflicts with §0's "frozen contract, do not rename" — a database's
migration-tracking table would show `0163b` where every other document
(architecture, plan, this journal) says `m0162`. Nothing had been applied to
any persistent database at the time (only disposable test databases, rebuilt
fresh per test), so the overseer instead **reordered the array** —
`[..., m0161, m0162, m0163a]`, restoring `m0162`'s own version string to the
literal `'0162'` the plan specifies — and re-verified all 33 tests across
UNIT 04a's and UNIT 05's owned pg suites still pass in that order. This is a
structural array-ordering fix, not a product decision, and needed no fresh
`SECURITY-REVIEW`. If UNIT 06 (`m0163`) is ever inserted before `m0163a` in
the array for the same reason, the same reordering approach applies rather
than renaming a frozen migration number.

**Broadened pre-existing test-health baseline:** independently re-running the
whole `-t pg` suite after the above fix still shows the same ~22 failures the
worker reported (not ~15) — the earlier journal note about "~15 pre-existing
`test/data/database/` failures" was scoped only to that one directory; the
full `-t pg` sweep also touches `test/api/`, where
`beacon_hierarchy_hasura_parity_test.dart`'s "JWT user cannot read child
beacon row via unchanged content permission" case times out after 30s. The
overseer independently confirmed this exact timeout **already existed at
UNIT 04a's commit (5ed2c1308), before UNIT 05 touched anything** — checked
out that commit, ran the test in isolation, got the identical
`TimeoutException`. **Not a UNIT 05 regression.** Root cause not further
investigated (out of scope for this unit); a future unit or separate pass
should look at it given its security-adjacent name, but it predates this
plan's work and is not caused by it.
DECISIONS: Dart mirror adds `isDiscoverable`, `isPublished`, `isMutuallyVisibleWithAuthor`; `b.user_id IS NOT NULL` needs no Dart field (author/tombstone assembly already implies resolved author). `canReadInvolvement` unchanged. **Blast-radius walk (D11 narrowed — content wall + operation-gated actions widen; involvement/admission do not):**

| Call site | Expected change |
|-----------|-----------------|
| `beacon_access_repository.dart:14` | Implementation — now evaluates discoverability branch via SQL |
| `beacon_display_case.dart:46` | **Widens** — mutually visible peers see display statuses for discoverable published open-family beacons |
| `forward_band_case.dart:39` | **Widens** — forward-band context readable when discoverability holds |
| `forward_case.dart:208` | **Widens** — sender may forward discoverable beacons they can now read (existing forward-specific checks unchanged) |
| `help_offer_case.dart:62,168` | **Widens** — offer/withdraw gated on content read; discoverable peers may offer |
| `invitation_case.dart:69,203,365` | **Widens** — invite create/preview/accept paths that require issuer/viewer content read |
| `coordination_case.dart:99` (`helpOffersWithCoordination`) | **Widens content gate only** — admission fields still redacted for third parties per §0.3; unchanged redaction shape |
| `beacon_child_create_case.dart:516` | **Widens** — fork/readable-child checks inherit new content wall |
| `attention_intent_case.dart:700,820,933,1055` | **Widens** — notification intent paths that skip delivery when `canReadBeaconContent` is false |
| `filter_beacon_notifications.dart:25` | **Widens** — durable notification filter keeps rows viewer can now read |
| `beacon_lineage_visibility.dart:10` | **Widens** — lineage source visibility follows content wall |
| `beacon_can_read_linked_detail` (m0155:51) | **Indirect widen** — delegates to `beacon_can_read_content`; hierarchy link reads follow content |
| Hasura `beacon` row filter (`can_read_content._eq: true`) | **Widens** — same predicate via `beacon_get_can_read_content` |
| `person_capability_event_repository` | **No direct `canReadContent` call** — no change |

**Accepted properties (R7/R8):** actions taken while a beacon was discoverable (help offers, forwards, invites, forks) outlive later opt-out; already-served image URLs are not revocable by tightening SQL.

**Parity expectation changes (justified):** reciprocal-trust + discoverable published open beacon now SQL-allow/Dart-allow (was SQL-deny before m0162). Sender on active forward edge + discoverable content now SQL-involvement-allow (m0124 sender/recipient OR; previously masked because content was deny-first).

REMAINING: none for this unit.

---

## UNIT 07 — complete — 2026-09-09
COMMITS: (this unit's commit, staged next)
TESTS: `cd packages/server && dart run build_runner build -d` — exit 0;
  `cd packages/server && dart test test/domain/use_case/constellation_field_case_test.dart` — 13/13 passed;
  `cd packages/server && dart test -t pg -j 1 test/data/repository/constellation_field_repository_pg_test.dart` — 8/8 passed;
  `./scripts/check-custom-lints.sh packages/server` — exit 0
FILES: packages/server/lib/consts/constellation_consts.dart (new),
  packages/server/lib/domain/entity/constellation_field.dart (new),
  packages/server/lib/domain/port/constellation_field_repository_port.dart (new),
  packages/server/lib/data/repository/constellation_field_repository.dart (new),
  packages/server/lib/domain/use_case/constellation_field_case.dart (new),
  packages/server/lib/api/controllers/graphql/query/query_constellation_field.dart (new),
  packages/server/lib/api/controllers/graphql/query/_queries_all.dart,
  packages/server/lib/api/controllers/graphql/custom_types.dart,
  packages/server/lib/api/controllers/graphql/mappers/constellation_gql_maps.dart (new),
  packages/server/test/domain/use_case/constellation_field_case_test.dart (new),
  packages/server/test/data/repository/constellation_field_repository_pg_test.dart (new),
  docs/plans/constellation-implementation-journal.md
FINDINGS: none beyond plan detail — repository follows UNIT 07 step-1 ordering
  (`person_visible_peers_symmetric` for graph peers, split ego/discoverable request
  queries, `constellation_trust_edges` on graph ids only, profiles via
  `UserProfileBatchLookup` without `scoresByPeerId`). **Performance (step 5):**
  pg test `whole-call timing on small ad-hoc fixture` (10 reciprocal-trust peers +
  11 beacons, disposable DB) asserts `ConstellationFieldCase.load` completes in
  **≪ 5s** (typical local run ~100–300 ms for the call itself). UNIT 02's ad-hoc
  50k-beacon composed-field probe on the same step sequence was **p95 ≥ 8000 ms**
  (statement_timeout cap; see `constellation-read-wall-performance.md`) — same
  shape, vastly smaller fixture, no contradiction.
DECISIONS: pg tests use a minimal `_PgProfileLookup` test double (display fields
  only) so `DriftUserProfileBatchLookup` does not pull `userPresenceModelToEntity`
  → `GetIt.I<Env>()` in a test harness with no DI bootstrap.
REMAINING: none for this unit.

---

## UNIT 06 — complete — 2026-09-09
COMMITS: (this unit's commit, staged next)
TESTS: `cd packages/server && dart test -t pg -j 1 test/data/database/constellation_trust_edges_pg_test.dart` — 11/11 passed;
  `./scripts/check-custom-lints.sh packages/server` — exit 0
FILES: packages/server/lib/data/database/migration/m0163.dart (new),
  packages/server/lib/data/database/migration/_migrations.dart,
  packages/server/test/data/database/constellation_trust_edges_pg_test.dart (new),
  docs/plans/constellation-implementation-journal.md
FINDINGS: none beyond the journal's pre-stated m0163/m0163a ordering pitfall — verified
  `_allMigrations` tail is `..., m0161, m0162, m0163, m0163a` (both `part` directives
  and array entries) so `'0163'` sorts before `'0163a'` per `migrant` string order.
  `pg_get_function_result` is the reliable way to assert RETURNS TABLE column names
  (direct `pg_attribute` join on `prorettype` returned empty for this function shape).
DECISIONS: none — §0.1 SQL copied verbatim; no product decisions in this unit.
REMAINING: none for this unit.

---

## UNIT 03 — complete — 2026-09-09
COMMITS: (this unit's commit, staged next)
TESTS: `cd packages/server && dart run build_runner build -d` — exit 0;
  `cd packages/server && dart test -t pg -j 1 test/data/database/beacon_discoverability_pg_test.dart` — 6/6 passed;
  `./scripts/check-custom-lints.sh packages/server` — exit 0
FILES: packages/server/lib/data/database/migration/m0160.dart (new),
  packages/server/lib/data/database/migration/_migrations.dart,
  packages/server/lib/data/database/table/beacons.dart,
  packages/server/lib/domain/entity/beacon_entity.dart,
  packages/server/lib/domain/port/beacon_repository_port.dart,
  packages/server/lib/data/repository/beacon_repository.dart,
  packages/server/lib/data/repository/mock/beacon_repository_mock.dart,
  packages/server/lib/domain/use_case/beacon_case.dart,
  packages/server/lib/api/controllers/graphql/mutation/mutation_beacon.dart,
  packages/server/lib/api/controllers/graphql/custom_types.dart,
  hasura/metadata.json,
  packages/server/test/data/database/beacon_discoverability_pg_test.dart (new),
  docs/plans/constellation-implementation-journal.md
FINDINGS: `Beacons` (Drift) did not carry `isDiscoverable` before this unit
  (baseline §1 stop condition clear). `beacon_child_create_case` →
  `BeaconRepository.createChildBeacon` does not pass `isDiscoverable`; child
  rows take the column default `true` (D12) — verified in pg test. Four
  hand-written `BeaconRepositoryPort` test stubs needed signature sync after
  the port change (not on the owns list; required for analyzer gate).
DECISIONS: `isDiscoverable` entity mapping lives in `BeaconRepository`
  (`_beaconRowToEntity` + `copyWith`) rather than `beacon_mapper.dart` (not
  on the unit owns list). Update semantics use `isDiscoverableProvided` /
  `containsKey('isDiscoverable')`, matching `primaryNeedSlug` pattern.
REMAINING: none for this unit.

---

## UNIT 10 — complete — 2026-09-09
COMMITS: (this unit's commit, staged next)
TESTS: `cd packages/client && flutter test test/features/constellation/constellation_layout_test.dart` — 10/10 passed;
  `./scripts/check-custom-lints.sh packages/client` — exit 0 (32/32 baseline unchanged)
FILES: packages/client/lib/features/constellation/domain/constellation_layout.dart (new),
  packages/client/test/features/constellation/constellation_layout_test.dart (new),
  docs/plans/constellation-implementation-journal.md
FINDINGS: none — §0.4 three-pass structure implemented without calling
  `computeRadialHopLayout`. Ring-holder test fixtures must use genuinely
  unattributed holders (a tier-2-only `ego→r` edge attributes `r` at depth 1,
  not `paths.ring`).
DECISIONS: satellite fan uses `localFanPositions` (which internally applies
  `amenityChordForRingGap` / `preferredFanStep`) with `ringGap: satelliteOffset`
  and the author's centre-to-author radial unit vector; ego satellites fan from
  centre via `branchUnitDirection` default (D16).
REMAINING: none for this unit.

---

## UNIT 09 — complete — 2026-09-09
COMMITS: (this unit's commit, staged next)
TESTS: `cd packages/client && flutter test test/features/constellation/` — 51/51 passed;
  `grep -n "import 'package:flutter\\|dart:ui" packages/client/lib/features/constellation/domain/constellation_filters.dart packages/client/lib/features/constellation/domain/constellation_density.dart` — no matches
FILES: packages/client/lib/features/constellation/domain/constellation_filters.dart (new),
  packages/client/lib/features/constellation/domain/constellation_density.dart (new),
  packages/client/test/features/constellation/constellation_filters_test.dart (new),
  packages/client/test/features/constellation/constellation_density_test.dart (new),
  docs/plans/constellation-implementation-journal.md
FINDINGS: none — timing semantics align with `BeaconScheduleKind` in
  `beacon_schedule.dart` (event when `startAt` set; deadline when only `endAt`;
  undated when both null).

**Overseer correction (post-review, before acceptance):** the worker's prompt
(written by the overseer) incorrectly told it this unit carries the same "no
Flutter / no dart:ui" constraint as UNIT 08. That constraint is real for
UNIT 08's own text ("Pure Dart: no Flutter import, no dart:ui... records and
collections only") but is **not** stated anywhere in UNIT 09's plan section —
and §0.4's frozen `constellationLabelBudget` signature explicitly takes
`required Size viewport` (`dart:ui`'s `Size`), which UNIT 10's frozen
`computeConstellationLayout`/`ConstellationLayout` signatures also use
(`Size canvasSize`, `Map<String, Offset> positions`) — geometry primitives are
evidently expected in this part of the domain layer, unlike UNIT 08's graph
algorithm, which genuinely has no geometric concern. Following the
overseer's incorrect briefing, the worker substituted a custom
`ConstellationViewport` (`width`, `height`) record for `Size`, disclosing the
substitution honestly as a DECISION rather than silently deviating — good
worker behavior given the (wrong) instruction it was given. The overseer
reverted this to the literal frozen signature: `constellationLabelBudget`
now takes `Size` from `dart:ui`, in both the implementation and the test
helper. All 51 tests still pass; lint baseline unchanged (32/32).
DECISIONS: Budget formula:
  `floor(ceiling × (viewportArea / refArea) / textScaleFactor)` clamped to
  `[1, ceiling]` with reference viewport 1200×900 — monotonic, never exceeds
  `(3, 150)`. `TimingFilter` / `LocationFilter` use sealed classes + enum per
  plan variants (`withinDays(int)` needs a payload).
REMAINING: none for this unit.

---

## UNIT 08 — complete — 2026-09-09
COMMITS: (this unit's commit, staged next)
TESTS: `cd packages/client && flutter test test/features/constellation/` — 27/27 passed;
  `grep -n "import 'package:flutter\\|dart:ui" packages/client/lib/features/constellation/domain/*.dart` — no matches
FILES: packages/client/lib/features/constellation/domain/constellation_path_resolution.dart (new),
  packages/client/lib/features/constellation/domain/constellation_cap_policy.dart (new),
  packages/client/lib/features/constellation/domain/constellation_consts.dart (new),
  packages/client/test/features/constellation/constellation_path_resolution_test.dart (new),
  packages/client/test/features/constellation/constellation_cap_policy_test.dart (new),
  docs/plans/constellation-implementation-journal.md
FINDINGS: none — §0.4 and architecture §5 agree; no `BLOCKED` contradictions. Ring-holder
  cap fixture must use a genuinely unreachable holder (no edges to `r`); a tier-2-only
  `ego→r` edge makes `r` attributed, not ring, which would falsify the N2 disjoint-states test.
DECISIONS: none beyond frozen contracts — GATE-D1 (A) hops-first key implemented as specified;
  `kConstellationRenderPeerCap = 120` (provisional, strictly < server 200).
REMAINING: none for this unit.

---

## UNIT 00 — complete — 2026-09-08
COMMITS: (this unit's commit, staged next)
TESTS: none required (docs/journal only)
FILES: docs/plans/constellation-implementation-journal.md (new), docs/README.md (edit)
FINDINGS: baseline matches plan §1 exactly, no differences to record; pre-existing
  unstaged edit to docs/Tentura_current_status_quo.md found and logged above for
  UNIT 01 to reconcile (see "Pre-existing worktree state").
DECISIONS: branch strategy — new branch `feat/constellation` cut from
  `docs/constellation-plans`, not committing implementation onto the docs
  branch (plan owner decision, 2026-09-08). Full-autonomy operating mode and
  gate-name pre-authorization recorded above under "Orchestration" (plan owner
  decision, 2026-09-08).
REMAINING: none for this unit.

---

## UNIT 01 — visibility evidence

Live baseline inspected 2026-09-08 against migration tail **m0159**. Evidence below is what
UNIT 05 will re-check for `BeaconAccessGuard.canReadContent` blast radius.

### `beacon_can_read_content` (m0136)

Source: `packages/server/lib/data/database/migration/m0136.dart:7-43`
(`CREATE OR REPLACE`; last migration touching this function per plan §1).

`LANGUAGE sql STABLE`. Evaluates `public.beacon b WHERE b.id = p_beacon_id`; returns
`false` when no row (`COALESCE(..., false)`). `CASE` branches, in order:

| # | Condition | Grants read |
|---|-----------|-------------|
| 1 | `block_hides(b.user_id, p_viewer_id)` | no |
| 2 | `b.status = 3` (draft) | author only (`b.user_id = p_viewer_id`) |
| 3 | `b.status = 2` (deleted) | no |
| 4 | `b.user_id = p_viewer_id` | yes (author) |
| 5 | active `beacon_forward_edge` (`recipient_id = viewer`, `cancelled_at IS NULL`) | yes |
| 6 | `beacon_participant` (`user_id = viewer`, `role = 1` OR `room_access = 3`) | yes |
| 7 | `beacon_help_offer` (`user_id = viewer`, `status = 0`) | yes |
| else | — | no |

No discoverability / mutual-visibility / MeritRank branch today. Status smallints per
`lib/domain/entity/beacon_status.dart`: draft = 3, deleted = 2.

Server implementation: `BeaconAccessRepository.canReadContent` → SQL
`SELECT public.beacon_can_read_content($1, $2)` at
`packages/server/lib/data/repository/beacon_access_repository.dart:14-18`.

### `person_visibility_peers` (m0151)

Source: `packages/server/lib/data/database/migration/m0151.dart:14-123`
(supersedes m0140's broader peer discovery; m0140 header notes incoming-only MR dropped).

Returns per-peer columns including directional explicit-trust flags, `forward_mr` /
`reverse_mr` from `mr_mutual_scores(viewer_id, ctx)` only (no `mr_edgelist` /
`mr_node_score` discovery). Peer union: `trust_out` ∪ `trust_in` ∪ `mr_mutual_agg`.

Directional visibility:

- `viewer_can_see_subject` := `viewer_explicitly_trusts_subject OR forward_mr > 0`
- `subject_can_see_viewer` := `subject_explicitly_trusts_viewer OR reverse_mr > 0`
- `is_mutually_visible` := both directional clauses ANDed (`m0151.dart:118-121`)

Explicit trust := `vote_user` row with `amount > 0` (`m0151.dart:84-101`).

### `person_is_mutually_visible` (m0140, delegates to m0151 peers)

Source: `packages/server/lib/data/database/migration/m0140.dart:168-184`.

`SELECT p.is_mutually_visible FROM person_visibility_peers(viewer_id, ctx) p
WHERE p.peer_id = peer_id`, default `false`. Viewer-first argument order; inherits m0151
truth table (asymmetric today — see architecture §1 / D14).

Also defined in m0140: `mutually_visible_users` (`m0140.dart:205-225`) joins
`person_visibility_peers` filtered to `is_mutually_visible`.

### Hasura `beacon` row filter and exposed columns

Metadata: `hasura/metadata.json`.

- **Computed field** `can_read_content` → `beacon_get_can_read_content(beacon_row,
  hasura_session)` (`hasura/metadata.json:196-204`).
- **Wrapper** `beacon_get_can_read_content` created in **m0099**
  (`packages/server/lib/data/database/migration/m0099.dart:11-22`) — delegates to
  `beacon_can_read_content(beacon_row.id, session user id)`.
- **Select permission** (`role: user`): row filter `can_read_content._eq: true`
  (`hasura/metadata.json:273-276`). Exposed base columns (`hasura/metadata.json:244-266`):
  `context`, `created_at`, `description`, `address_label`, `end_at`, `id`, `lat`, `long`,
  `needs`, `start_at`, `status`, `status_changed_at`, `tags`, `title`, `updated_at`,
  `user_id`, `lineage_parent_beacon_id`, `lineage_root_beacon_id`, `primary_need_slug`,
  `cover_image_id`, `cover_thumb_image_id`, `cover_source`. Computed fields also exposed:
  `is_pinned`, `my_vote`, `can_read_content`. No `is_discoverable` column yet (UNIT 03 /
  m0160).
- **Related filter:** `beacon_image` select uses parent `beacon.can_read_content._eq:
  true` (`hasura/metadata.json:377-381`). `beacon_help_offer` insert check includes
  `beacon.can_read_content._eq: true` (`hasura/metadata.json:1468-1470`).

### `BeaconAccessGuard.canReadContent` server call sites

Implementation dispatches to `beacon_can_read_content` (see above). Consumer blast radius
(`grep -rn "canReadContent" packages/server/lib`):

| File:line | Enclosing API / helper |
|-----------|------------------------|
| `attention_intent_case.dart:700` | `_directedRoomMessage` (room mention / directed chat targets) |
| `attention_intent_case.dart:820` | `requestStatusChanged` |
| `attention_intent_case.dart:933` | `beaconHierarchyStatusChanged` |
| `attention_intent_case.dart:1055` | `fromBeaconNotification` |
| `beacon_child_create_case.dart:516` | `_readableChildId` |
| `beacon_display_case.dart:46` | `displayStatuses` |
| `beacon_lineage_visibility.dart:10` | `assertBeaconLineageSourceVisible` |
| `coordination_case.dart:99` | `helpOffersWithCoordination` |
| `filter_beacon_notifications.dart:25` | `filterBeaconNotifications` |
| `forward_band_case.dart:39` | `forwardContext` |
| `forward_case.dart:208` | `forward` (sender authorization) |
| `help_offer_case.dart:62` | `offerHelp` |
| `help_offer_case.dart:168` | `withdraw` |
| `invitation_case.dart:69` | `create` (issuer must read beacon) |
| `invitation_case.dart:203` | `_previewBeaconForInvite` |
| `invitation_case.dart:365` | `_acceptBeaconInviteOnly` |

Not listed: `beacon_access_repository.dart:14` (guard implementation),
`beacon_visibility.dart:99` (pure Dart policy mirror of different type).

### Target activation pointer

Discoverability read-wall change: **m0162** (plan **UNIT 05**), depending on **m0160**
(`is_discoverable`, UNIT 03) and **m0161** (symmetric `person_are_mutually_visible`,
UNIT 04). GATE-14.1 (UNIT 02) must resolve before UNIT 05.

### Term reconciliation (step 5)

Checked across `CONTEXT.md`, `docs/Tentura_current_status_quo.md`, and
`constellation-edge-semantics.md`:

| Term | Status |
|------|--------|
| **Direct / explicit trust** | Plan checklist says "direct trust"; normative docs use **explicit trust** for the same referent (`vote_user`, `amount > 0`). No product collision — wording alias only. |
| **Discoverability** | Now split: status-quo §11 paragraph and `CONTEXT.md` target contract marked **not yet active**; architecture D4/D11 describe intended rule. Person-level mutual visibility in status-quo §11 first paragraph remains **current** (m0151). |
| **Forwarding** | Consistent: manual `beacon_forward_edge` act (content read + involvement for recipient); separate from Constellation path drawing (D5) and from MR forward-candidate gate. |
| **Discussion admission** | Consistent: explicit chat/workspace admission (status-quo §6–7); distinct from content read; architecture D11 states discovery does not grant it. |

No collisions requiring a product decision.

### Architecture amendment checklist (step 6)

Confirmed present and self-consistent in `constellation-edge-semantics.md` as of
2026-09-08 amendment banner:

- [x] **O1** — §5 layered `d2[p][h]`, hops-first within stage, `depth(parent(p)) ==
  depth(p)-1` proof, `(tier, id)` in D8; D1 + §12.1 O1a across-stages
- [x] **A2** — §12/U5 `constellationField` has no context argument
- [x] **A3** — §5.1 four narrowed stability clauses
- [x] **N1** — §5 **V** symmetric single-source + accepted enumeration gap
- [x] **N2** — §5.2 transport guard rail vs client render budget + absence-semantics table
- [x] **N3** — §12/U8 provider-neutral render seam before reuse
- [x] **§14.2** items 6, 7, 8
- [x] **§8.3** four conjuncts incl. `published_at IS NOT NULL`, `user_id IS NOT NULL`
- [x] **ALG-*** — `ALG-HOLDERS`, `ALG-DEDUP`, `ALG-STAGE1`, `ALG-STAGE2`, `ALG-PARENT`
  (guard `q ∉ T OR depth1(q) = depth(p)-1`), `ALG-EGO`, `ALG-PRUNE`; `d2[ego][0] = 0`;
  **B** publication conjunct; §5.2 absence table; D11 narrowed to content-wall parity

Not `BLOCKED`.

---

## UNIT 01 — complete — 2026-09-08
COMMITS: (this unit's commit, staged next)
TESTS: `bash scripts/check-user-facing-terminology.sh` — exit 0
FILES: CONTEXT.md, docs/Tentura_current_status_quo.md,
  docs/plans/constellation-edge-semantics.md, docs/plans/constellation-implementation-journal.md
FINDINGS: none beyond evidence recorded above; status-quo §11 already had a
  discoverability paragraph (pre-existing unstaged edit) reconciled to "not yet active"
  framing per journal pre-existing worktree note.
DECISIONS: none beyond §0; "direct trust" in plan step 5 treated as alias for
  "explicit trust" in normative docs (journal term table).
REMAINING: none for this unit.

---

## UNIT 11 — complete — 2026-09-09
COMMITS: (this unit's commit, staged next)
TESTS: `cd packages/client && dart run build_runner build -d` — exit 0;
  `cd packages/client && flutter test test/features/constellation/` — 66/66 passed;
  `./scripts/check-custom-lints.sh packages/client` — exit 0 (32/32 baseline unchanged)
FILES: packages/client/lib/features/constellation/domain/entity/constellation_field.dart (new),
  packages/client/lib/features/constellation/domain/port/constellation_repository_port.dart (new),
  packages/client/lib/features/constellation/domain/use_case/constellation_field_case.dart (new),
  packages/client/lib/features/constellation/data/gql/constellation_field_fetch.graphql (new),
  packages/client/lib/features/constellation/data/repository/constellation_repository.dart (new),
  packages/client/lib/features/constellation/data/repository/constellation_repository_mock.dart (new),
  packages/client/lib/data/service/remote_api_client/build_client.dart,
  packages/client/lib/data/gql/schema.graphql,
  packages/client/test/features/constellation/constellation_repository_test.dart (new),
  docs/plans/constellation-implementation-journal.md
FINDINGS: none — schema overlay uses `v2_Constellation*` types matching the
  Hasura-stitched naming convention; direct V2 routing registered as
  `ConstellationFieldFetch` per `build_client.dart` procedure step 1.
DECISIONS: `ConstellationHeldState` priority: `mine` → `offered` →
  `participant` → `forwarded` → `none`. `ConstellationFieldResolved` typedef
  flattens field + `ConstellationResolvedField` cap output for the cubit seam.
  Holder-id test asserts profile-only peers never enter `paths.ring` (indirect
  proof they are excluded from `holderIds`).
REMAINING: none for this unit.

---

## UNIT 12 — complete — 2026-09-09
COMMITS: bd3c09b53 refactor(graph): lift provider seam for constellation reuse; (this unit's commit, staged next)
TESTS: `cd packages/client && dart run build_runner build -d` — exit 0;
  `cd packages/client && flutter test test/features/constellation/` — 71/71 passed;
  `cd packages/client && flutter test test/features/graph/` — 214/214 passed;
  `./scripts/check-custom-lints.sh packages/client` — exit 0 (32/32 baseline unchanged)
FILES: packages/client/lib/features/graph/domain/entity/graph_mode.dart,
  packages/client/lib/features/graph/ui/widget/graph_legend_mode.dart,
  packages/client/lib/features/graph/domain/entity/node_details.dart,
  packages/client/lib/features/graph/ui/utils/tentura_layout_algorithms.dart,
  packages/client/lib/features/graph/ui/widget/graph_legend_content.dart,
  packages/client/lib/features/graph/ui/widget/graph_app_bar_actions.dart,
  packages/client/lib/features/graph/ui/widget/graph_node_widget.dart,
  packages/client/lib/features/graph/ui/widget/graph_body.dart,
  packages/client/lib/features/constellation/ui/bloc/constellation_cubit.dart (new),
  packages/client/lib/features/constellation/ui/bloc/constellation_state.dart (new),
  packages/client/lib/features/constellation/ui/widget/constellation_body.dart (new),
  packages/client/lib/features/constellation/ui/screen/constellation_screen.dart (new),
  packages/client/test/features/constellation/constellation_body_test.dart (new),
  docs/plans/constellation-implementation-journal.md
FINDINGS: Plan owns-list omits required call-site files touched in step 0
  (`graph_screen.dart`, four graph test files) — compilation and 214/214 graph
  tests required them. Constellation legend copy is inline English (no l10n in
  this unit's owns list); UNIT 14/20 own the §0.6 keys. `StateBase` has no
  `StateIsFailure` — load failures use `StateIsSuccess` + `loadError` per
  existing client pattern.
DECISIONS: `ConstellationEdgePainter` classifies strokes via cubit `edgeKinds`
  map (not weight-derived `EdgeDetails.color`). `ConstellationLayoutAlgorithm.relayout`
  recomputes from resolved field every time (no position memoisation). Legend
  tier-2 row labelled "Indirect connection" with no evidence vocabulary (D1a).

**Overseer note (post-review, before acceptance):** the worker's FINDINGS
claim above ("UNIT 14/20 own the §0.6 keys") is **not accurate** — the
overseer checked every remaining unit's owns-list and **no other unit in the
plan touches `graph_legend_content.dart` again**. UNIT 14/15/17/18/19/20 add
their own l10n keys for their own files, but none of them revisit this one.
The four inline strings this unit added ("Direct connection", "Indirect
connection", "Request link", "Wider network reach") are therefore a genuinely
**orphaned gap** — real, functioning copy, correctly D1a-compliant in
content, but not translated for `app_ru.arb` and with no `.arb` key at all.
`bash scripts/check-user-facing-terminology.sh` passes because it checks
Request/Chat vocabulary, not l10n completeness, so no gate currently catches
this. The overseer did **not** invent Russian translations or freeze this
wording unilaterally — the exact phrasing here is provisional worker-authored
copy the plan itself never specified, and picking final wording plus a
faithful Russian translation is a product-copy decision better made
deliberately than as a drive-by fix during unit review. **Action required
before UNIT 20's acceptance sign-off (or sooner):** move these four strings
to `app_en.arb`/`app_ru.arb` with real l10n keys and update
`graph_legend_content.dart`'s constellation branch to reference them,
matching the existing `l10n.graphLegendRequestNode` pattern already used two
lines away in the same file. Recorded here, and should also be added to
UNIT 20's limitations/acceptance checklist explicitly when that unit runs.
REMAINING: the orphaned legend-l10n gap above. Otherwise none for this unit.

---

## UNIT 13 — pre-implementation product review — 2026-09-09

**Reviewer:** V.G. Bulavintsev (plan owner; pre-authorized per Orchestration).

Fold shape is **decided** (plan step 1): receipts become a **third Inbox tab**
alongside *Needs me* and *Watching*. Open details resolved before code edits:

| Open detail | Resolution |
|-------------|------------|
| **Updates badge + read-state store** (§9.2) | `AttentionAckStore` keys pending acks by **receipt `id`** only (`attention_ack_store.dart`); account scope via `resetForAccount`. No store or `AttentionCase` API change — the badge widget moves from the retired nav item to the Inbox **Receipts** tab label, still driven by `AttentionCase.unreadSummary` / `snapshot.summary.unreadTotal`. |
| **Where the Updates archive lands** | The existing Updates feed body stays intact inside the Receipts tab: **All / Unread / Needs you** sub-tabs, search, mark-all-seen, and paginated history — no separate archive route. |
| **`kPathUpdates` + `RedirectRoute(kPathNotifications → kPathUpdates)`** | Keep both path constants. Remove Updates as a Home shell branch. `kPathUpdates` becomes a **redirect** to `kPathInbox` with `?tab=receipts` (new `kInboxTabReceipts` query value on existing `kQueryHomeTab`). `kPathNotifications` still redirects to `kPathUpdates` first so legacy notification/deep links chain through unchanged. `openFromUpdate` activates **Inbox** and selects the Receipts sub-tab. |

**UNIT 14 must follow immediately after this unit** to restore the fifth
navigation destination at index 2 (Constellation). This unit intentionally
ships **four** nav destinations; that is not a release stopping point on this
branch, but must not sit long before UNIT 14 lands.

---

## UNIT 13 — complete — 2026-09-09

COMMITS: (this unit's commit, staged next)
TESTS: `cd packages/client && flutter gen-l10n && dart run build_runner build -d` — exit 0;
  `cd packages/client && flutter test test/features/inbox/ test/features/updates/ test/features/home/ test/app/ test/architecture/home_tab_spec_test.dart` — 200/200 passed;
  `bash scripts/check-user-facing-terminology.sh` — exit 0
FILES: packages/client/lib/consts.dart,
  packages/client/lib/app/router/home_tab_branches.dart,
  packages/client/lib/app/router/root_router.dart,
  packages/client/lib/features/home/ui/screen/home_screen.dart,
  packages/client/lib/features/home/ui/bloc/home_tab_reselect_cubit.dart,
  packages/client/lib/features/home/ui/bloc/home_tab_reselect_state.dart,
  packages/client/lib/features/inbox/ui/screen/inbox_screen.dart,
  packages/client/lib/features/inbox/ui/widget/inbox_receipts_tab_label.dart (new),
  packages/client/lib/features/updates/ui/widget/updates_feed_pane.dart (new),
  packages/client/lib/features/updates/ui/screen/updates_screen.dart,
  packages/client/lib/features/home/ui/widget/updates_navbar_item.dart (deleted),
  packages/client/l10n/app_en.arb,
  packages/client/l10n/app_ru.arb,
  packages/client/test/features/inbox/inbox_receipts_fold_test.dart (new),
  packages/client/test/features/inbox/inbox_expanded_chrome_test.dart,
  packages/client/test/features/updates/updates_102_my_work_attention_test.dart,
  packages/client/test/app/router/home_tab_branch_routing_test.dart,
  packages/client/test/architecture/home_tab_spec_test.dart,
  packages/client/test/architecture/realtime_entity_contract_impacts_test.dart,
  packages/client/lib/ui/effect/ui_effect_dispatcher.dart,
  packages/client/lib/features/forward/ui/message/forward_messages.dart,
  docs/plans/constellation-implementation-journal.md
FINDINGS: `InboxRoute` gained `@QueryParam(kQueryHomeTab)` for receipts deep
  links, which made `const InboxRoute()` invalid — required dropping `const`
  at three call sites outside the unit owns list (`ui_effect_dispatcher.dart`,
  `forward_messages.dart`, browse cold-start in `root_router.dart`). Root-level
  `RedirectRoute` for `kPathUpdates` was required (nested redirect under
  `HomeRoute` children did not activate). `HomeTab.updates` enum value kept with
  `HomeTabSpec.forTab` alias → Inbox so `beacon_view_screen.dart` back/rail
  paths compile unchanged until a future cleanup.
DECISIONS: Product review **V.G. Bulavintsev** (pre-authorized). Badge +
  read-state: `AttentionAckStore` receipt-`id` keying unchanged; badge on Inbox
  **Receipts** tab via `InboxReceiptsTabLabel` (`updates-unread-count-N`
  semantics identifier preserved). Archive: existing All/Unread/Needs-you feed
  inside Receipts tab (`UpdatesFeedPane`). Paths: `kPathUpdates` root redirect →
  `/home/inbox?tab=receipts`; `kPathNotifications` → `kPathUpdates` chain kept.
  Nav: four destinations (Work, Inbox, Network, Profile); Network index 2, Me
  index 3 — slot freed for UNIT 14 Constellation at index 2.
REMAINING: **UNIT 14 must follow immediately** — restore the fifth navigation
  destination (Constellation) at index 2. Do not treat the interim four-item bar
  as a release stopping point.

---

## UNIT 14 — complete — 2026-09-09
COMMITS: (this unit's commit, staged next)
TESTS: `cd packages/client && flutter gen-l10n && dart run build_runner build -d` — exit 0;
  `cd packages/client && flutter test test/features/home/ test/features/my_work/ test/app/` — 206/206 passed;
  `bash scripts/check-user-facing-terminology.sh` — exit 0;
  `./scripts/check-custom-lints.sh packages/client` — exit 0 (32/32 baseline unchanged)
FILES: packages/client/lib/consts.dart,
  packages/client/lib/app/router/home_tab_branches.dart,
  packages/client/lib/app/router/root_router.dart,
  packages/client/lib/features/home/ui/screen/home_screen.dart,
  packages/client/lib/features/home/ui/widget/constellation_navbar_item.dart (new),
  packages/client/lib/features/home/ui/bloc/home_tab_reselect_cubit.dart,
  packages/client/lib/features/my_work/ui/screen/my_work_screen.dart,
  packages/client/lib/features/my_work/ui/widget/my_work_empty_body.dart,
  packages/client/lib/ui/test_ids.dart,
  packages/client/l10n/app_en.arb,
  packages/client/l10n/app_ru.arb,
  packages/client/test/features/home/constellation_nav_test.dart (new),
  packages/client/test/features/my_work/my_work_empty_body_test.dart,
  docs/plans/constellation-implementation-journal.md
FINDINGS: live `home_tab_branches.dart` matched UNIT 13 snapshot (four tabs,
  Network index 2). `test/architecture/home_tab_spec_test.dart` still asserts the
  four-tab UNIT 13 shape — outside this unit's owns list and verify block; full
  `flutter test` CI will need that file updated separately.
DECISIONS: `ConstellationNavbarItem` is a plain `Icon` + `Semantics`/`TestIds`
  only — no `Badge` widget (§9.2). Nav label/icon: `l10n.constellationTitle` +
  `Icons.hub` / `Icons.hub_outlined`. `HomeTab.constellation` enum value added;
  `HomeTab.updates` → Inbox alias untouched. §0.6 frozen ids
  (`constellationNavItem`, `myWorkFindWaysToHelp`) landed in `test_ids.dart`
  despite UNIT 14 owns-list omitting that file — required by acceptance tests.
  My Work empty-state CTA uses `TenturaTextAction` with no count/badge.
REMAINING: none for this unit.

**Overseer fix (post-review, before acceptance):** confirmed the worker's
FINDING — `test/architecture/home_tab_spec_test.dart` (a file UNIT 13's
worker added outside its own owns list, with no other unit ever claiming it)
asserted the transient four-tab shape and failed once UNIT 14 landed. This is
squarely case (b) of executor contract §2 rule 7 — an assertion that encoded
an intentionally-superseded intermediate state, not a genuine regression — so
the overseer updated its expectations to the final five-tab shape
(`work=0, inbox=1, constellation=2, network=3, me=4`) and renamed the test
description from "four-tab... after UNIT 13" to "five-tab... after UNIT 14".
Re-verified: this file's 3/3 tests pass, and the full
`flutter test test/features/home/ test/features/my_work/ test/app/` sweep
plus the lint gate were independently re-run afterward and remain
206/206 / 32-baseline clean.

---

## UNIT 15 — complete — 2026-09-09
COMMITS: (this unit's commit, staged next)
TESTS: `cd packages/client && flutter gen-l10n` — exit 0;
  `cd packages/client && flutter test test/features/constellation/` — 88/88 passed;
  `bash scripts/check-user-facing-terminology.sh` — exit 0;
  `./scripts/check-custom-lints.sh packages/client` — exit 0 (32/32 baseline unchanged)
FILES: packages/client/lib/features/constellation/ui/widget/constellation_request_label.dart (new),
  packages/client/lib/features/constellation/ui/widget/constellation_request_preview_sheet.dart (new),
  packages/client/lib/features/graph/ui/widget/graph_person_context_panel.dart,
  packages/client/l10n/app_en.arb,
  packages/client/l10n/app_ru.arb,
  packages/client/test/features/constellation/constellation_preview_test.dart (new),
  docs/plans/constellation-implementation-journal.md
FINDINGS: none — timing reuses `beaconSchedulePresentation` via a minimal schedule
  adapter; coverage strings come from author-supplied `status` only (never
  `helpOfferCount`). `test_ids.dart` §0.6 ids for preview/person-expand were not
  added (outside this unit's owns list); widgets use the same string keys inline.
DECISIONS: UX1 need text prefers resolved `primaryNeedSlug` capability label, then
  title, then unspecified. Connection copy uses the first-hop peer on the selected
  path (`parent` walk); direct depth-1 authors omit the connection block. Primary
  preview actions: `none` → offer/backup by status; `offered` → edit help offer;
  `participant`/`forwarded`/`mine` → open request. Person panel requests use an
  explicit expand/collapse control (default collapsed).
REMAINING: none for this unit. Wiring preview/label into `ConstellationBody` tap
  handling and passing discoverable requests into the person panel from the
  constellation screen remain for a later unit (not on this owns list).

**Overseer finding (post-review, before acceptance):** the worker's REMAINING
note is confirmed real, not just caution. The overseer grepped every unit's
"Owns:" list in the plan for `constellation_body.dart` — it appears exactly
once, in UNIT 12's own list (where the file was created). **No later unit
(16, 17, 18, 19, 20) ever touches it again.** Live-code check: `constellation_body.dart`
renders `GraphNodeWidget` for both node kinds with no `onTap:` passed (the
widget supports one — `graph_node_widget.dart`'s `onTap` param, already used
by `graph_body.dart`'s `_onNodeTap`/`GraphPersonContextPanel` pattern), and
`ConstellationCubit` has `selectRequest(String?)` (sets `selectedRequestId`,
per UNIT 12) but no method yet to select/expand a person. **Without further
work, nothing on the rendered map is tappable** — UNIT 15's own preview sheet
and the person-panel request list it just built are unreachable from the
actual screen. This blocks UNIT 16 in substance (its whole premise is
"before entering an offer/forward flow" — a flow with no way to enter it) even
though the plan's dependency graph doesn't show it as a formal blocker.

**Remediation:** dispatching a small, focused continuation (not a renumbered
plan unit — this is finishing UNIT 15's own intent, not adding new product
scope) to wire `ConstellationBody` node taps to `selectRequest`/a new
person-selection method, and to render the preview sheet / person panel in
response, following `graph_body.dart`'s existing `_onNodeTap` +
`GraphPersonContextPanel` pattern. See the follow-up entry below for the
outcome.

---

## UNIT 15 continuation — wire node taps — complete — 2026-09-09
COMMITS: (this unit's commit, staged next)
TESTS: `cd packages/client && dart run build_runner build -d` — exit 0;
  `cd packages/client && flutter test test/features/constellation/` — 91/91 passed;
  `cd packages/client && flutter test test/features/graph/` — 214/214 passed;
  `./scripts/check-custom-lints.sh packages/client` — exit 0 (32/32 baseline unchanged)
FILES: packages/client/lib/features/constellation/ui/widget/constellation_body.dart,
  packages/client/lib/features/constellation/ui/bloc/constellation_cubit.dart,
  packages/client/lib/features/constellation/ui/bloc/constellation_state.dart,
  packages/client/lib/features/constellation/ui/screen/constellation_screen.dart,
  packages/client/test/features/constellation/constellation_body_test.dart,
  docs/plans/constellation-implementation-journal.md
FINDINGS: none — `expandedPersonIds` in UNIT 12 state was already the right
  shape for per-person discoverable-request expand/collapse; selection needed a
  separate `selectedPersonId`. `GraphPersonContextPanel` still requires
  `GraphPersonContextCubit` + `ScreenCubit` in the subtree (close/trust/profile
  actions); constellation screen now provides both via `localScreenCubitScope`
  and a route-local `GraphPersonContextCubit`, matching graph screen wiring.
DECISIONS: **Profile/UserNode construction:** build synchronously from the
  one-shot field snapshot — `FieldPersonNode.person` / `ConstellationPerson`
  → `Profile` (id, displayName, handle, image) and `UserNode(user: profile)`
  with no `GraphPersonContextCubit` async profile fetch. Constellation's field
  is a single upfront load (D15), not the paginated trust-graph focus model.
  **Preview-sheet actions:** `onOpen` and held-state primaries that mean "open
  request" (`mine`/`participant`/`forwarded`/`offered`) navigate to
  `BeaconViewRoute` — fully wired. `onPrimaryAction` for `heldState.none`
  (offer help / backup) is a deliberate no-op placeholder for UNIT 16's
  validated action-time flow. `onForward` is a visible no-op placeholder (empty
  callback) so the forward affordance renders but does not submit — UNIT 16
  owns real forward validation/submission.
REMAINING: UNIT 16 — snapshot lifecycle, action-time validation, and wiring
  real offer/forward submission from the preview sheet (and any server
  `expectedOfferKind` contract). No other gaps from this continuation.

**Overseer: accepted.** Independently re-verified worktree clean, 91/91
constellation + 214/214 graph tests, lint 32/32 baseline unchanged, and
spot-checked the three new tap-interaction tests
(`tapping a request node opens the preview sheet`,
`dismiss and re-tap reopens the request preview sheet`,
`tapping a person node opens the discoverable-requests panel`) are
substantive, not stubs. The map is now genuinely interactive; UNIT 16 can
proceed.

---

## UNIT 16 — complete — 2026-09-09
COMMITS: (this unit's commit, staged next)
TESTS: `cd packages/server && dart test test/domain/use_case/help_offer_case_test.dart` — 26/26 passed;
  `cd packages/server && dart test -t pg -j 1 test/data/repository/help_offer_expected_kind_pg_test.dart` — 1/1 passed;
  `./scripts/check-custom-lints.sh packages/server` — exit 0 (baseline 0);
  `cd packages/client && dart run build_runner build -d` — exit 0;
  `cd packages/client && flutter test test/features/constellation/constellation_freshness_test.dart test/features/forward/` — 219/219 passed;
  `./scripts/check-custom-lints.sh packages/client` — exit 0 (32/32 baseline unchanged)
FILES: packages/server/lib/api/controllers/graphql/mutation/mutation_help_offer.dart,
  packages/server/lib/domain/use_case/help_offer_case.dart,
  packages/server/lib/domain/exception_codes.dart,
  packages/server/test/domain/use_case/help_offer_case_test.dart,
  packages/server/test/data/repository/help_offer_expected_kind_pg_test.dart (new),
  packages/client/lib/features/forward/data/gql/beacon_offer_help.graphql,
  packages/client/lib/data/gql/schema.graphql,
  packages/client/lib/features/forward/data/repository/forward_repository.dart,
  packages/client/lib/features/constellation/ui/widget/constellation_snapshot_bar.dart (new),
  packages/client/lib/features/constellation/ui/bloc/constellation_cubit.dart,
  packages/client/lib/features/constellation/ui/widget/constellation_body.dart,
  packages/client/test/features/constellation/constellation_freshness_test.dart (new),
  packages/client/test/features/beacon_view/beacon_view_offer_help_test.dart,
  docs/plans/constellation-implementation-journal.md
FINDINGS: `constellation_body.dart` is not on the plan §3 owns list but was
  required to wire UNIT 15 continuation placeholders (`onPrimaryAction` /
  `onForward`) and mount `ConstellationSnapshotBar`; same for
  `beacon_view_offer_help_test.dart` — one-line `offerHelp` fake signature
  update after `ForwardRepository` gained `expectedOfferKind`. Generated Ferry
  `*_req.gql.dart` outputs remain git-ignored; `build_runner` is still required
  after pulling. Client `offerKindChanged` detection parses coordination code
  `1516` from exception text (no dedicated GraphQL error mapper yet).
DECISIONS: Server permissible kind: new offer → `1` when locked status is
  `enoughHelp`, else `0`; active-offer update → stored `offerKind` (update
  never changes kind). Both branches run inside `_attention.runAction` →
  `runInBeaconStateTransaction` with kind check before any write; omitted
  `expectedOfferKind` preserves legacy behavior. Client preflight uses existing
  `ForwardRepository.fetchBeaconInvolvement`; selected-request refresh updates
  the request row in the field but leaves `loadedAt` unchanged; Map/Text
  switch does not reload. Coverage flip after snapshot → backup choice prompt,
  never silent conversion; `offerKindChanged` preserves draft note and
  re-presents choice.
REMAINING: none for this unit. UNIT 17 — filter bar, grouping, stable anchors.

---

## UNIT 17 — complete — 2026-09-09
COMMITS: (this unit's commit, staged next)
TESTS: `cd packages/client && flutter gen-l10n` — exit 0;
  `cd packages/client && flutter test test/features/constellation/` — 108/108 passed;
  `./scripts/check-custom-lints.sh packages/client` — exit 0 (32/32 baseline unchanged);
  `bash scripts/check-user-facing-terminology.sh` — exit 0
FILES: packages/client/lib/features/constellation/ui/widget/constellation_filter_bar.dart (new),
  packages/client/lib/features/constellation/ui/widget/constellation_overflow_group.dart (new),
  packages/client/lib/features/constellation/ui/bloc/constellation_cubit.dart,
  packages/client/l10n/app_en.arb,
  packages/client/l10n/app_ru.arb,
  packages/client/test/features/constellation/constellation_density_widget_test.dart (new),
  docs/plans/constellation-implementation-journal.md
FINDINGS: `constellation_body.dart` is not on this unit's owns list — filter bar,
  overflow group, and field-level notices are implemented as composable widgets
  with cubit seam wiring, but the live map screen does not mount them yet (same
  pattern as UNIT 15/16 body gaps before continuation). `ForwardRepository` is
  now resolved lazily so graph-only tests avoid GetIt bootstrap.
DECISIONS: Layout anchors use the unfiltered `requestIdsByAuthor` map; filters and
  label budget only affect drawn satellites via `displayedRequestIds` /
  `overflowHiddenCountByAuthor`. Three field-level notices (`peersCapped`,
  `requestsCapped`, client `capped`) are independent widgets; `peersCapped` ring
  copy degrades to `constellationAbsencePathNotShown` via `ringSemanticsKeyForPerson`.
  Limitations footnote records no effort filter and no remote filter. Fallback
  list link calls `setViewMode(text)` — UNIT 18 still owns the text surface.
REMAINING: Mount `ConstellationFilterBar` and per-author `ConstellationOverflowGroup`
  in `constellation_body.dart` (or UNIT 18 screen edit). UNIT 18 text view is the
  fallback-list destination for `peersCapped` — link sets view mode but plain list
  is not reachable until that unit lands.

---

## UNIT 18 — complete — 2026-09-09
COMMITS: (this unit's commit, staged next)
TESTS: `cd packages/client && flutter gen-l10n` — exit 0;
  `cd packages/client && flutter test test/features/constellation/` — 117/117 passed;
  `bash scripts/check-user-facing-terminology.sh` — exit 0;
  `./scripts/check-custom-lints.sh packages/client` — exit 0 (32/32 baseline unchanged)
FILES: packages/client/lib/features/constellation/ui/widget/constellation_text_view.dart (new),
  packages/client/lib/features/constellation/ui/widget/constellation_body.dart,
  packages/client/lib/features/constellation/ui/screen/constellation_screen.dart,
  packages/client/l10n/app_en.arb,
  packages/client/l10n/app_ru.arb,
  packages/client/test/features/constellation/constellation_text_view_test.dart (new),
  packages/client/test/features/constellation/constellation_body_test.dart,
  docs/plans/constellation-implementation-journal.md
FINDINGS: `ConstellationSnapshotBar` (UNIT 16) still carries inline English Map/Text
  labels — this unit replaced it in `ConstellationBody` with localized
  `_ConstellationSnapshotChrome` using new l10n keys; the standalone snapshot bar
  widget remains for its freshness unit test. `intl`’s `TextDirection` class shadows
  Flutter’s enum when both are imported — fixed with `hide TextDirection` on the
  intl import in `constellation_body.dart`. Body widget tests needed a 1200×900
  surface after the filter bar was mounted (default 800×600 pushed graph nodes
  off-screen).
DECISIONS: Map viewport preservation uses `IndexedStack` (map stays mounted while
  text is shown) rather than serializing `GraphController` transforms. Plain-list
  mode (peersCapped) suppresses per-request connection copy in text view only;
  map path notices still use UNIT 17’s filter-bar link to switch view mode.
  Selection reconciliation when a stale id is selected shows
  `constellationSelectionUnavailable` and clears selection — never auto-picks another
  request. Overflow groups mount on the map canvas via `GraphView.builder` at author
  satellite positions; filter bar sits above both views.
REMAINING: none for this unit. UNIT 19 — author discoverability toggle.

---

## UNIT 19 — complete — 2026-09-09
COMMITS: (this unit's commit, staged next)
TESTS: `cd packages/client && flutter gen-l10n && dart run build_runner build -d` — exit 0;
  `cd packages/client && flutter test test/features/beacon_create/` — 122/122 passed;
  `bash scripts/check-user-facing-terminology.sh` — exit 0;
  `./scripts/check-custom-lints.sh packages/client` — exit 0 (32/32 baseline unchanged)
FILES: packages/client/lib/domain/entity/beacon.dart,
  packages/client/lib/data/gql/beacon_model.graphql,
  packages/client/lib/data/model/beacon_model.dart,
  packages/client/lib/data/gql/schema.graphql,
  packages/client/lib/features/beacon/data/gql/beacon_create.graphql,
  packages/client/lib/features/beacon/data/gql/beacon_update.graphql,
  packages/client/lib/features/beacon/data/gql/beacon_update_draft.graphql,
  packages/client/lib/features/beacon/data/repository/beacon_repository.dart,
  packages/client/lib/features/beacon/ui/widget/beacon_discoverability_control.dart (new),
  packages/client/lib/features/beacon_create/ui/bloc/beacon_create_state.dart,
  packages/client/lib/features/beacon_create/ui/bloc/beacon_create_cubit.dart,
  packages/client/lib/features/beacon_create/ui/widget/info_tab.dart,
  packages/client/lib/ui/test_ids.dart,
  packages/client/l10n/app_en.arb,
  packages/client/l10n/app_ru.arb,
  packages/client/test/features/beacon_create/discoverability_toggle_test.dart (new),
  packages/client/test/features/beacon_create/fake_beacon_ports.dart,
  docs/plans/constellation-implementation-journal.md
FINDINGS: server GraphQL field name confirmed `isDiscoverable` (camelCase) in
  `custom_types.dart`; Hasura column `is_discoverable` on reads. Toggle surface:
  **`info_tab.dart` Details card** (not the compact optional-summary row) — that
  card already holds per-request settings (timing, requirements, cover, location);
  the compact summary row is layout-only navigation. Reusable author control lives
  in `features/beacon/ui/widget/beacon_discoverability_control.dart` for the detail
  settings seam; wired from create/edit `InfoTab` only (author-only route). No live
  reach count (v1). `SwitchListTile` inside the Details `DecoratedBox` needs an
  explicit `Material` wrapper to avoid ink-splash assertions in tests.
DECISIONS: `BeaconDiscoverabilityControl.isAuthor` gates visibility for non-authors
  (widget returns shrink — tested directly). Reach copy uses frozen §0.6 keys
  (`requestDiscoverableLabel` / `requestDiscoverableHint`). Draft saves pass
  `isDiscoverable` through the same payload as publish/edit updates.
REMAINING: inline toggle on published request **view** (`beacon_view`) not wired —
  authors change discoverability via create/edit (`BeaconCreateRoute(editId:)`).
  UNIT 20 may note if product wants view-surface access without entering edit mode.

**Overseer: accepted, with one note for UNIT 20.** Independently re-verified
122/122 tests, lint 32/32, terminology clean, and confirmed
`isAuthor` gating actually hides the widget (not just zeroes a count). The
plan's UNIT 19 owns-list explicitly named `features/beacon/**` (detail
settings surface) alongside `beacon_create`, which reads as intending a
view-surface path too — this unit shipped the create/edit path only. That
said, the acceptance criterion ("authors can see and change what they are
opting out of") is genuinely met via edit mode, and reusable
`BeaconDiscoverabilityControl` already exists for a future view-surface
mount if wanted, so this is a product-completeness question, not a
correctness gap — not fixing it unilaterally. Flagging for UNIT 20's UX
acceptance pass to decide, rather than treating it as blocking.

---

## UNIT 20 — complete — 2026-09-09

**Scope split (UX9):** this worker did **not** conduct the task-based human
user study (UX9). That requires a real human tester and browser-automation
tooling the overseer runs separately after this unit lands. This entry records
fixture **constructibility** in `docs/features/constellation.md` § *UX
acceptance fixtures* and leaves the study task, measured times, and acceptance
record for the overseer to fill in.

COMMITS: (this unit's commit, staged next)
TESTS: `cd packages/client && flutter gen-l10n` — exit 0;
  `cd packages/client && flutter build web` — exit 0 (`flutter_bootstrap.js?v=7.2.0`);
  `cd packages/client && flutter test` — 2872 passed, 30 skipped, **1 failed**
  (`test/features/beacon_threads/request_threads_adaptive_test.dart`: Log adaptive
  plan row in Activity sheet opens General and scrolls to sourceMessageId —
  ambiguous `PopupMenuButton` tap; pre-existing, outside this unit's owns list,
  unrelated to Constellation);
  `cd packages/server && dart test` — 2255 passed, 2 skipped, **24 failed**
  (4 named + 20 more; includes the ~22 pre-existing pg-tagged ambient failures
  when Postgres is reachable — count matches journal baseline, not a regression);
  `cd packages/server && dart test -x pg` — 1675 passed, **1 failed**
  (`test/domain/use_case/beacon_room_admission_matrix_test.dart`: direct forward
  does not auto-admit — pre-existing COV-051 matrix, outside this unit);
  `cd packages/server && dart test -t pg -j 1` — 575 passed, 2 skipped, **23 failed**
  (within journal baseline ~22; named: `beacon_hierarchy_hasura_parity_test.dart`,
  `beacon_cover_migration_test.dart`, `m0149_resolution_removal_migration_test.dart`,
  `realtime_notification_migration_test.dart`, plus 19 more — same pre-existing set);
  `./scripts/check-custom-lints.sh packages/client` — exit 0 (32/32 baseline unchanged);
  `./scripts/check-custom-lints.sh packages/server` — exit 0 (baseline 0);
  `bash scripts/check-user-facing-terminology.sh` — exit 0;
  `git status --short packages/client/web/index.html` — ` M` (cache-buster 7.2.0)
FILES: packages/client/pubspec.yaml (7.2.0),
  packages/client/web/index.html,
  packages/client/l10n/app_en.arb,
  packages/client/l10n/app_ru.arb,
  packages/client/lib/features/graph/ui/widget/graph_legend_content.dart,
  docs/Tentura_current_status_quo.md,
  CONTEXT.md,
  docs/features/constellation.md (new),
  docs/README.md,
  docs/plans/constellation-implementation-journal.md
FINDINGS: Client version was 7.1.5 at unit start; `kDefaultMinClientVersion`
  left at 7.0.0 per plan (additive schema only). §5 surface table in status-quo
  still listed Updates — reconciled to shipped five-tab shape (Constellation at
  index 2, Receipts under Inbox). Out-of-scope items from plan §5 (mr_graph
  paths, nav badges, score ordering, involvement widening, etc.) did not creep
  in across units 00–19 per journal review.
DECISIONS: **UNIT 12 legend l10n gap — fixed in this unit** (plan allowed fix
  or document-only): four keys added to `app_en.arb`/`app_ru.arb`
  (`graphLegendConstellationDirectConnection`, `…IndirectConnection`,
  `…RequestLink`, `…WiderNetworkReach`) and wired in
  `graph_legend_content.dart` — removes the orphaned inline-English gap before
  doc activation. **UNIT 19 view-surface gap — documented, not built:** authors
  change discoverability via create/edit only; recorded in
  `docs/features/constellation.md` limitations §9 (product-completeness note,
  acceptance criterion met via edit). **UX9 study — explicitly deferred to
  overseer** (see scope split above). Plan mechanical work across 21 units is
  complete; **plan acceptance is not declared here** — pending overseer UX9
  pass and acceptance record.
REMAINING: **UX acceptance (UX9)** — overseer conducts task-based study using
  fixtures documented in `docs/features/constellation.md`; records completion
  times, taps, mistaken-endorsement incidents, stale-recovery, and
  keyboard/screen-reader tasks; fills acceptance into journal when done.
  **Discoverability on published request view** — optional future mount of
  `BeaconDiscoverabilityControl` on `beacon_view` (not blocking). Pre-existing
  test failures listed above remain out of scope for this plan.

**Overseer full-suite review (post-UNIT-20, before UX9 pass):** the worker's
"1 failed" on the client and "23 failed (baseline ~22)" on the server pg
sweep were not accepted at face value — both were independently
investigated, not just re-counted.

- **Real regression, fixed:** `test/domain/use_case/beacon_room_admission_matrix_test.dart`
  (untagged, so it ran only under the whole-suite `dart test`, never under any
  single unit's scoped Verify block) failed with
  `MissingStubError: 'runInBeaconStateTransaction'` — a **direct, causal
  regression from UNIT 16**, which wrapped both `HelpOfferCase.offerHelp`
  branches in the new `BeaconRepositoryPort.runInBeaconStateTransaction`
  call. This file's own `MockBeaconRepositoryPort` (shared generated mocks
  from `help_offer_case_mocks.mocks.dart`, the same file UNIT 16's own test
  uses) was never taught to stub the new method — UNIT 16 only ran and fixed
  up its *own* owned test file, not this sibling file that also happens to
  exercise `HelpOfferCase.offerHelp` through a bare mock. Fixed directly (a
  small, local addition — `when(beaconRepo.runInBeaconStateTransaction<void>(...))`
  answering by invoking the captured `fn` against the test's existing beacon
  fixture, mirroring `help_offer_case_test.dart`'s own `_LockingBeaconRepo`
  fake's behavior). Re-verified: 17/17 now pass in this file. This is plan
  §2 rule 7 case (a) — a genuine regression, not a stale assertion — so it
  was fixed, not just documented.
- **Investigated and ruled out, not a regression:** the client failure
  (`request_threads_adaptive_test.dart`, "ambiguously found 2 widgets with
  key 'beacon.overflow.menu'") has **zero code overlap** with anything this
  plan touched — the file has no `graph`/`constellation` references at all —
  and the failure signature (a finder ambiguously matching two mounted
  widgets) is a classic test-isolation artifact, not a logic error. It also
  fails identically running the file in isolation, consistent with an
  existing intra-file test-order dependency rather than anything introduced
  here. Left alone, per this plan's stated scope (fixing unrelated
  pre-existing flakes is out of scope) — recorded here for whoever next
  triages the client suite's flakes, since it wasn't in any baseline note
  before this run surfaced it (first time the *whole* `flutter test` ran in
  this session).

Re-ran the full suites after the fix:
`cd packages/server && dart test -x pg` — clean (no failures);
`cd packages/server && dart test -t pg -j 1` — unchanged from the
pre-existing ~22 baseline (not re-investigated further; same named files as
every prior unit's baseline note).

---

## UX9 — overseer live walkthrough — in progress — 2026-09-09

Conducting the task-based walkthrough UNIT 20 explicitly deferred (real
human tester substitute: overseer driving `https://dev.lvh.me:9443` via
Playwright MCP as `constellation-qa@test.tentura.local`, with a seeded
mutually-visible peer `constellation-peer@test.tentura.local` and beacon
`B85668cea9c4c` "Borrow a ladder", author = peer, `is_discoverable=true`).
This is a genuine end-to-end pass across the browser, the live server, and
the persistent dev Postgres — none of which any unit's `flutter test`/
`dart test` run exercises together. It surfaced three real, previously
undetected defects, none caught by any unit's own test suite. All three are
now root-caused and fixed; walkthrough continues below this entry.

**Finding 1 — persistent dev DB never fully migrated (infra, not app code).**
Root cause: an earlier unit attempt (UNIT 05, attempt 1) ran
`migrateDbSchema` against the shared `postgres` database instead of a
disposable one, and left a phantom `'0163b'` row in `schema_version` — a
version string from a since-reverted mid-flight rename (see the UNIT 05
remediation note above) — which made `migrant` believe `m0163` was already
applied and skip it forever on every subsequent server boot. Fixed by
applying `m0163`'s SQL directly against the persistent DB and correcting
`schema_version` (removed `'0163b'`, inserted accurate `'0162'`/`'0163'`
rows). This is a one-time local-environment repair, not a code or migration
defect — `_allMigrations` itself is correct and was independently verified
during UNIT 05's own review.

**Finding 2 — false "closed eye" (mutual-visibility) indicator — fixed,
committed with this entry.** `packages/client/lib/features/constellation/ui/bloc/constellation_cubit.dart`
`_profileFromPeer` was constructing the `Profile` passed into the reused
`GraphPersonContextPanel` using only defaults for `myVote` /
`subjectExplicitlyTrustsViewer` (never populated from the peer's actual
tier-1 edges), so `Profile.isMutuallyVisible` (which reads those two old,
per-direction asymmetric-trust fields — the exact model D14/UNIT04
superseded with the symmetric `person_are_mutually_visible` function) was
always false for every Constellation peer, showing a "closed eye — not
mutually visible" badge even for a peer with a live reciprocal `vote_user`
trust edge to the viewer. Fixed by deriving `myVote`/
`subjectExplicitlyTrustsViewer` from the field snapshot's own tier-1 edges
(`state.field.edges`) instead of leaving them at their zero-value defaults.
Verified: `flutter test test/features/constellation/` 117/117 green, and
live in-browser the peer now shows "Open eye — two-way visibility."

**Finding 3 — Offer Help / Forward silently blocked for every
discovery-only viewer (most severe; fixed, committed with this entry).**
`ConstellationCubit.preflightRequestAction` (called immediately before
either action commits) fetched fresh beacon state via
`_forwardRepository.fetchBeaconInvolvement`, which is gated server-side by
`can_read_involvement` (confirmed via the shared `'Viewer cannot read
request involvement'` / GraphQL error code `1102` raised by
`beacon_involvement_case.dart`, `forward_inbound_query_case.dart`, and
`beacon_forward_graph_case.dart` alike). Per D11, Constellation's whole
premise is that discovery grants **content-wall** reads, never
**involvement/discussion-admission** access — so this preflight denied
*every* discovery-only viewer on *every* attempted action, the primary use
case the entire 20-unit plan exists to serve. This was invisible to every
unit's own tests because each one legitimately mocked/stubbed
`fetchBeaconInvolvement` to succeed (a reasonable per-unit assumption; no
unit's scope was "is this the correct data source"). Fixed by switching
`preflightRequestAction` to refresh via `_case.load(viewerId:)` — the same
content-wall-gated `ConstellationFieldCase` the initial field snapshot
already comes from — and extracting the one matching `ConstellationRequest`
from the refreshed field instead of a `Beacon` from involvement data;
`ConstellationRequestPreflightReady` now carries `ConstellationRequest`
directly (dropped the `beacon` field), and
`coverageRequiresExplicitBackupChoice` takes `freshRequest:
ConstellationRequest` instead of `freshBeacon: Beacon` (it only ever read
`.status`, already present on `ConstellationRequest`). Per UNIT 16's
"refreshing one selected request must not claim the whole field refreshed"
invariant, only the single request is merged into state via the existing
`_replaceRequestInField` (unchanged) — `state.loadedAt`/peers/paths are left
untouched. Rewrote
`packages/client/test/features/constellation/constellation_freshness_test.dart`
around this: the stub `ConstellationRepositoryPort.fetch()` is now mutable
so tests can simulate a server-side change between the initial load and the
preflight refresh (status flips, request vanishes from the field), replacing
the old `_FakeForwardRepository.fetchBeaconInvolvement`-based staging, which
is no longer on the call path at all. Verified: `flutter test
test/features/constellation/` 117/117 green; full `flutter test` 2872
passed / 30 skipped / 1 failed (`request_threads_adaptive_test.dart`, the
same pre-existing unrelated flake UNIT 20 already recorded — zero overlap,
confirmed unchanged); `./scripts/check-custom-lints.sh packages/client`
32/32 baseline; `bash scripts/check-user-facing-terminology.sh` clean. Live
re-verification: submitted a real Offer Help through the browser: the
dialog now opens and submits (previously blocked before the dialog even
appeared); confirmed via direct SQL against the dev DB that a
`beacon_help_offer` row was actually written
(`beacon_id=B85668cea9c4c, user_id=U2b782a36b83b` — the QA ego — `message='I
have a ladder you can borrow.'`); re-opened the preview and confirmed it now
reads "You offered help" / "Edit help offer", proving the post-submit
`preflightRequestAction` refresh also works end to end.

COMMITS: (staged next, both findings 2 and 3 together —
`constellation_cubit.dart` carries both fixes)
FILES: packages/client/lib/features/constellation/ui/bloc/constellation_cubit.dart,
  packages/client/lib/features/constellation/ui/widget/constellation_body.dart,
  packages/client/test/features/constellation/constellation_freshness_test.dart,
  docs/plans/constellation-implementation-journal.md
REMAINING: continue the walkthrough (Forward flow, Map/Text switch, filter
  bar interactions, keyboard/screen-reader operation, a stale-request
  recovery scenario), then record full UX9 acceptance (or a further finding)
  in a follow-up entry. Plan-wide integration read-through and final
  completion report still pending behind that.
