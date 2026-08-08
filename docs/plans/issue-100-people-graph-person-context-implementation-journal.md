# Issue #100 implementation journal

## Scope and baseline

- **Objective:** execute `issue-100-people-graph-person-context-implementation-plan.md` end to end.
- **Repository / branch / starting HEAD:** `/home/vader/MY_SRC/tentura`, `main`, `c094c40a9ae317c9c3ea1b45de1c1de38fc933ee`.
- **Plan source:** `docs/plans/issue-100-people-graph-person-context-implementation-plan.md`.
- **Workflow:** sequential fresh `cursor-agent` workers, pinned to non-fast `composer-2.5`; no resume, push, reset, stash, generated-file edits, or unrelated staging.

## Preserved pre-existing worktree changes

Modified:

- `docs/README.md`
- `docs/archive/journals/commitment-truth-rework-journal.md`
- `docs/archive/plans/commitment-truth-rework-plan.md`
- `docs/audits/room-coordination-audit.md`
- `docs/plans/room-composer-clipboard-paste-implementation-journal.md`
- `packages/server/lib/data/database/table/beacon_commitment_events.dart`
- `packages/server/lib/env.dart`

Untracked:

- `dart-defines`
- `docs/plans/graph-navigation-implementation-guide.md`
- `docs/plans/graph-navigation-rework-plan.md`
- `docs/plans/issue-100-people-graph-person-context-implementation-plan.md`
- `docs/plans/received-reviews-trust-changes-plan.md`
- `docs/plans/room-composer-clipboard-paste-plan.md`
- `graph-ego-neighbors-layout-issue.md`
- `key.fb`
- `out.key`
- `product_testing_compact_buglist.md`
- `product_testing_detailed_report.md`

## Ordered manifest

1. **WU0** — preflight and characterization — **complete** (2026-08-08).
2. **WU1** — database, Hasura, and V2 visibility boundary — pending.
3. **WU2** — client profile projection and canonical getters — pending.
4. **WU3** — server enforcement and candidate discovery — pending.
5. **WU4** — graph modes and reactive navigation — pending.
6. **WU5** — People entry points — pending.
7. **WU6** — Blocked People route ownership — pending.
8. **WU7** — policy and Profile hierarchy — pending.
9. **WU8** — mandatory first human usability check — pending human gate.
10. **WU9** — graph profile projection patch and equality — pending.
11. **WU10** — authoritative Trust and context cubit — pending.
12. **WU11** — Person Context presentation — pending.
13. **WU12** — accessibility and pointer affordance — pending.
14. **WU13** — localization — pending.
15. **WU14** — mandatory visual-association human gate — pending human gate.
16. **WU15** — conditional AppBar cleanup after WU14 pass — pending.
17. **WU16** — version, compatibility, and full regression — pending.

## Preflight evidence

### #86 ownership (re-run 2026-08-08)

```bash
git worktree list --porcelain
# ~/MY_SRC/tentura c094c40a [main]

git merge-base --is-ancestor 22f9d35d HEAD
# exit 0

gh issue view 86 --json state
# {"state":"CLOSED"}

gh pr list --state open --search '86 in:title,body'
# No Pull Requests
```

- One worktree; `22f9d35d` is an ancestor of `HEAD` (`c094c40a`); issue #86 closed; no open PR owns graph navigation.
- **Stop condition not triggered:** safe to proceed to WU1 when authorized.

### Live worktree snapshot (2026-08-08)

`git status --short` matches the preserved list above; no new modified or untracked paths beyond the journal itself after WU0.

### Version / cache / migration / metadata (2026-08-08)

| Item | Live value |
|---|---|
| Client `pubspec.yaml` version | `5.8.0` |
| `web/index.html` bootstrap cache key | `flutter_bootstrap.js?v=5.8.0` |
| Server `kDefaultMinClientVersion` (`env.dart`) | `5.6.38` (pre-existing local modification; unchanged by WU0) |
| Next migration part | **`m0140`** — `_migrations.dart` ordered list ends at `m0139`; no `m0140` part exists yet |
| Hasura `trusts_viewer` | absent (`rg` on `hasura/metadata.json`: no matches) |
| Hasura `mutually_visible_users` | absent |

## WU0 — characterization test results (2026-08-08)

All baseline tests **passed**. No pre-existing failures observed.

### Client (`packages/client`)

```bash
flutter test test/features/graph/graph_focus_path_visibility_test.dart \
  test/features/graph/graph_body_navigation_controls_test.dart \
  test/features/graph/graph_cubit_genealogy_test.dart \
  test/features/graph/graph_body_genealogy_test.dart \
  test/features/graph/graph_body_select_expand_test.dart \
  test/features/graph/forward_graph_focus_rules_test.dart \
  test/app/router/home_tab_branch_routing_test.dart \
  test/features/block/ui/sheet/block_user_sheet_test.dart \
  test/ui/widget/contact_badge_legend_test.dart
```

**Outcome:** `00:03 +110: All tests passed!` (exit 0)

Per-file counts: `graph_focus_path_visibility_test.dart` 37; `graph_body_navigation_controls_test.dart` 6; `graph_cubit_genealogy_test.dart` 16; `graph_body_genealogy_test.dart` 3; `graph_body_select_expand_test.dart` 4; `forward_graph_focus_rules_test.dart` 7; `home_tab_branch_routing_test.dart` 20; `block_user_sheet_test.dart` 13; `contact_badge_legend_test.dart` 4.

### Server (`packages/server`)

```bash
dart test --exclude-tags pg test/domain/use_case/forward_case_test.dart \
  test/domain/use_case/forward_case_auth_test.dart
```

**Outcome:** `00:00 +30: All tests passed!` (exit 0)

## Existing test traceability (WU0 characterization map)

| Contract | Primary test file(s) | Representative test name(s) |
|---|---|---|
| Reset preserves `_everFocusedIds` | `graph_focus_path_visibility_test.dart` | `resetToEgo keeps everFocused so rollback taps do not refetch` |
| New-node explore vs visited-node rollback | `graph_focus_path_visibility_test.dart`, `graph_body_select_expand_test.dart` | `rollback tap on ancestor with hidden badge does not fetch`; `tap sequence A→B→E→back-to-B spotlights the ego→focus path and backtracking refetches nothing`; `tap on unexpanded node expands once`; `tap on already expanded node selects without fetching` |
| Cached path reconstruction | `graph_focus_path_visibility_test.dart` | `teleport select rebuilds focus path through cached edges after resetToEgo`; `adjacent hop appends to focus path even when a shorter chord exists` |
| Genealogy focus behavior | `graph_cubit_genealogy_test.dart`, `graph_body_genealogy_test.dart` | `genealogy parent-chain nodes pin on first exploration tap and remain visible`; `genealogy exploration hides sibling branches while keeping the parent chain`; `genealogy tap on parent chain after sibling spotlight selects only`; `genealogy mode ignores context and positive-only controls`; widget: `GraphBody wires withRating for GenealogyUserNode` |

**Decision:** do not duplicate these tests in WU0; extend them in later work units only when asserted state must change (per plan §6).

## Verification matrix

- Per-unit commands and all plan-final client/server/custom-lint/terminology/graph-package checks from WU16.
- PostgreSQL evidence remains required for WU1 and final verification; SQLite-only results cannot accept the visibility SQL.

## Unresolved gates and decisions

- WU8 and WU14 require an unbriefed human participant. Automated tests cannot substitute; WU15 cannot begin unless WU14 evidence passes.
- Preserve all listed pre-existing changes and never stage or commit them.
- WU0 made **no production or generated file changes**.

---

## WU0 final entry — 2026-08-08

**Status:** complete

**Worker:** fresh Cursor agent (composer-2.5), WU0 only.

**Actions performed:**

1. Re-ran §3.1 #86 ownership commands — all green.
2. Re-captured `git status --short`, version/cache/migration/metadata snapshot.
3. Confirmed next migration is `m0140` (`m0139` is last registered part).
4. Ran all 11 client + 2 server characterization test files from plan §6 — all passed.
5. Mapped existing tests to reset/rollback/cached-path/genealogy contracts (table above).
6. Verified no production or generated files were edited.

**Commits:** see below (journal only).

**Findings:**

- Baseline is clean: 140 characterization tests (110 client + 30 server), zero failures.
- `env.dart` remains locally modified (pre-existing); `kDefaultMinClientVersion` read as `5.6.38` but not touched.
- Hasura metadata has no `trusts_viewer` or `mutually_visible_users` yet — expected pre-WU1 state.
- `graph_body_navigation_controls_test.dart` still expects `home recenters without clearing focus trail` (camera-only reset); plan WU4 will replace this when trust Reset calls `resetToEgo()`.

**Remaining:** WU1 — canonical visibility at database and API boundary.

---

## Manager review — WU0 accepted (2026-08-08)

- Inspected `967152cd` and confirmed it contains only the journal.
- Re-ran the complete characterization matrix independently: 110 client and 30 server tests passed.
- `git show --check 967152cd` and the live worktree diff check passed.
- **Verdict:** accepted. WU1 may begin; all preserved unrelated changes remain unstaged.
