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
- [ ] 01 — Visibility docs, evidence, architecture amendments
- [ ] 02 — **Gate:** authorization cache + read-wall performance decision
- [ ] 03 — `beacon.is_discoverable` — m0160, Drift, mutations, Hasura
- [ ] 04 — Symmetric `person_are_mutually_visible` — m0161
- [ ] 05 — Read-wall discoverability clause — m0162 **(access-control; needs GATE-14.1 resolved + SECURITY-REVIEW)**
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

None yet.

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
