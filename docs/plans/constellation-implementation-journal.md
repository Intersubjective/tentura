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
- [ ] 05 — Read-wall discoverability clause — m0162 **(access-control; needs GATE-14.1 resolved + SECURITY-REVIEW; now also depends on 04a)**
- [ ] 06 — `constellation_trust_edges` — m0163
- [ ] 07 — `constellationField` V2 query
- [ ] 08 — Client pure domain: paths, caps
- [ ] 09 — Client pure domain: filters, density
- [ ] 10 — Client pure domain: three-pass layout
- [ ] 11 — Client data: entities, gql, repository, use case
- [ ] 12 — Render: mode, nodes, edges, painters, legend
- [ ] 13 — Prerequisite project: fold Updates into Inbox
- [ ] 14 — Navigation slot, route, My Work entry
- [ ] 15 — Need labels, request preview, person panel
- [ ] 16 — Snapshot lifecycle + action-time validation, incl. server `expectedOfferKind`
- [ ] 17 — Filter bar, grouping, stable anchors
- [ ] 18 — Accessible Map/Text switch
- [ ] 19 — Author discoverability toggle + reach statement
- [ ] 20 — Version bump, docs activation, UX acceptance

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
