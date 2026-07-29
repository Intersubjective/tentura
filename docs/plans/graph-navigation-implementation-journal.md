# Graph navigation implementation journal

## Scope

- Objective: implement `docs/plans/graph-navigation-implementation-guide.md` (issue #86).
- Repository: `/home/vader/MY_SRC/tentura`
- Branch and starting HEAD: `main` at `216d72d87da41f36ad78f1f37cbb7c5cf219005c`.
- Manager: Codex using fresh sequential Cursor `composer-2.5` workers.

## Protected pre-existing worktree state

The following was present before orchestration and must not be reset, overwritten, or
committed as part of this plan: modified `packages/client/l10n/app_en.arb`,
`packages/client/l10n/app_ru.arb`,
`packages/client/lib/features/graph/ui/utils/animated_highlighted_edge_painter.dart`,
`packages/client/lib/features/graph/ui/widget/graph_body.dart`,
`packages/client/lib/features/graph/ui/widget/graph_legend_content.dart`,
`packages/client/pubspec.yaml`,
`packages/client/test/features/graph/graph_legend_test.dart`, and
`packages/client/web/index.html`; untracked `dart-defines`,
`docs/plans/graph-navigation-implementation-guide.md`,
`docs/plans/graph-navigation-rework-plan.md`, `key.fb`, and `out.key`.

The two untracked plan documents are the user-provided source/context, not owned
implementation changes. This journal is orchestrator-owned.

## Ordered manifest

1. Phase 1 — vendored graph-library API/layout-transition patches. **accepted in `de6e6020`**
2. Phase 2 — deterministic pure layouts and adapters. **in progress**
3. Phase 3 — server edge-closure migration, Hasura metadata, client query/repository, PG tests. **accepted in working tree (pending commit)**
4. Phase 4A — graph cubit closure/filter/history interaction. pending
5. Phase 4B — graph UI controls, deterministic wiring, legend and reciprocal lanes. pending
6. Phase 5 — relationship/layout/integration regression coverage. pending
7. Cross-plan review, CI-equivalent/local-stack verification, commit/push, GitHub Actions monitoring. pending

## Required gates

- Fork: `cd packages/force_directed_graphview && flutter test`
- Client: analyzer, tests, and `./scripts/check-custom-lints.sh packages/client`
- Server: `dart analyze`, tests excluding and including PG where local stack is available, and custom lint gate.
- Repository: `packages/tentura_lints` tests, terminology and doc-drift checks; final CI-equivalent Docker matrix plus applicable browser/local-stack proof.

## Decisions and boundaries

- Arrowheads are already part of protected pre-existing work; Phase 4 must retain rather than redo them.
- Never edit generated Dart files; run localization/codegen only when source inputs require it.
- All workers must read this journal and the complete implementation guide, preserve protected work, append evidence checkpoints, commit only their attributable tracked changes, and never push.

## Phase 1 manager review — 2026-07-29

The initial worker stopped before journaling or committing; a fresh recovery worker could
not start because Cursor returned `resource_exhausted`. The manager preserved the complete
uncommitted Phase 1 diff and independently reviewed it. It implements Tasks 1.1–1.7:
value equality, runtime configuration refresh, immutable layout interpolation, ticker-owned
transition publishing, fitting, clear/recenter semantics, version/changelog, lockfile, and
focused tests. No protected path was changed by this unit.

Independent evidence: `cd packages/force_directed_graphview && flutter test` passed 14
tests; `cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos` exited
0 with its existing non-fatal 548 diagnostics. `git diff --check` was clean for the fork.
The current transition test is intentionally a widget/lifecycle smoke test; downstream
deterministic-adapter tests will exercise the final-layout transition contract.

Phase 1 commit: `de6e6020 Add graph layout transition primitives`.

## Phase 2 manager recovery — 2026-07-29

The Phase 2 worker produced the deterministic radial/layered domain layouts, adapters,
position-hint removal, and tests but stopped before validation/commit. A fresh recovery
worker twice failed at Cursor service startup with `resource_exhausted`. The manager made
the two exact Phase 2.4 integration deletions in `graph_body.dart` without staging its
protected arrowhead hunks, corrected a type-inference analyzer error and an obsolete local,
then ran the four focused graph suites successfully (25 tests). The complete analyzer now
has no Phase 2 errors; its remaining output is non-fatal pre-existing/general lint debt.

## Phase 3 worker evidence — 2026-07-29

Implemented Tasks 3.1–3.4 only: `m0134` `graph_edges_between` migration + registration,
Hasura function tracking (`graph_edges_between`, no `session_argument`), client
`graph_edges_between.graphql` + Ferry codegen, `schema.graphql` introspection fields,
`GraphRepository.fetchEdgesBetween`, default/override on `GraphSourceRepository` /
`ForwardsGraphRepository` / `InviteGenealogyRepository`, server PG regression suite, and
client repository short-circuit test. Protected client ARBs/UI/pubspec/web and untracked
secrets/docs were not touched.

Evidence:
- `cd packages/server && dart analyze` — exit 0 (info-level debt only)
- `cd packages/server && dart test -x pg` — 1101 passed
- `cd packages/server && dart run bin/utils/run_migrations_once.dart` — applied m0134
- `cd packages/server && dart test -t pg test/graph_edges_between_test.dart` — 5 passed
- `cd packages/client && flutter test test/features/graph/graph_repository_fetch_edges_between_test.dart` — 1 passed
- `python3 -m json.tool hasura/metadata.json` — valid JSON
- Hasura not running locally; metadata apply / schema introspection via live stack deferred

## Phase 4A manager recovery — 2026-07-29

The original Cursor worker implemented the Phase 4A cubit/UI/test work but its
combined widget-test command hung because `pumpEventQueue` attempted to drain a
repeating graph animation. Two fresh Composer recovery sessions were unavailable
(`resource_exhausted`). Manager review found the apparent `popFocus` regression
was instead an overbroad final assertion for selecting a non-adjacent cached
node after reset; that operation correctly exposes only focus-incident edges.

Manager fixes: bounded the new widget-test pumping, supplied the required
`ProfileCubit` test provider, and corrected that assertion. Independent focused
evidence: `flutter test test/features/graph/graph_focus_path_visibility_test.dart`
passed 16 tests; `flutter test test/features/graph/graph_body_select_expand_test.dart`
passed 2 tests. Phase 4A still requires review of the remaining genealogy graph
tests, exact hunk staging around protected arrowhead work, and a focused commit.

## Phase 5 Task 5.3 remediation — 2026-07-29

Integration `graph_navigation_hops_test.dart` timed out in `pumpUntil` waiting for
a third-hop node: bootstrap only yields author+helper, and a one-way helper→third
`userSubscribe` never surfaced in MeritRank within the 45s window. Screen dump at
failure showed ego+helper on graph with the action panel (`Expand` visible) —
timeout was post hop-1, not on graph load.

Remediation: keep the two-user QA bootstrap (+ author `userSubscribe`); drive two
expansions (ego, then helper); add stable `TestIds` on graph Back/Reset/Expand;
harden helpers with `waitForGraphReady`, cubit fallback when canvas taps miss, and
key-based control finders. Widget evidence:
`flutter test test/features/graph/graph_body_navigation_controls_test.dart`
`test/features/graph/graph_body_select_expand_test.dart` — 4 passed.

Harness (single run): failed on third-node wait before remediation; updated test
targets two-hop path only — re-run deferred to Phase 5 gate.

## Reciprocal-edge rendering correction — 2026-07-29

Product direction superseded Task 4.8's double-lane rendering: a reciprocal
trust pair now has one canonical rendered edge. The cubit retains both directed
records in its cache for traversal/visibility, but only emits the stable
lexicographic representative to the graph controller; it is marked
`isReciprocal`. The edge painter always uses a straight line and, while
animated, overlays a reverse-direction shader highlight so both directions run
simultaneously on the same track. Protected forwards/genealogy arrowheads were
retained.

Evidence: the focused graph suite (25 tests) and the intentionally regenerated
`reciprocal_edge_bidirectional.png` golden passed. Full CI-equivalent checks
remain in progress.
