# Implementation journal — Request detail NOW / CHAT / People

**Plan source:** `docs/plans/request-detail-now-chat-people-plan.md` (rev 2, post adversarial review)
**Repository:** `/home/vader/MY_SRC/tentura`
**Branch:** `feat/request-detail-now-chat-people`
**Starting HEAD:** `40fd7bae188c9f8ef5ecbae03615450dd1cb0391` (`fix(server): let m0158's cleanup bypass the lifecycle write-guard it hits`)
**Base branch:** `main` (branched off; do NOT commit to main)
**Orchestrator:** Claude Code overseer. Workers: `cursor-agent --model composer-2.5`, one at a time, fresh session each.

---

## READ THIS FIRST (every worker)

1. Read this whole journal before inspecting or editing anything.
2. Read `AGENTS.md` and the `.cursor/rules/*.mdc` files its index points at for your unit.
3. Read the **whole** plan section for your unit before editing. Live code wins over stale plan prose — if they conflict, follow live code and record the conflict in a FINDINGS entry here.
4. Implement **only your assigned unit**, but complete it end to end.
5. Commit early and often: one focused commit per completed coherent step, immediately after verifying that step. Do not bundle the whole unit into one commit. **Never push.**
6. Append a checkpoint entry below during work, and a final entry before exit.

---

## Pre-existing worktree state (PRESERVE — not ours, do not commit, do not delete)

`git status --porcelain` at start showed **zero tracked modifications** and these untracked paths:

```
CLAUDE.local.md
dart-defines
docs/plans/algorithm-invariant-suites-plan.md
docs/plans/availability-request-receptiveness-architecture.md
docs/plans/availability-request-receptiveness-implementation-plan.md
docs/plans/availability-review-codex.md
docs/plans/availability-review-grok46.md
docs/plans/availability-review-kimik3.md
docs/plans/graph-navigation-implementation-guide.md
docs/plans/graph-navigation-rework-plan.md
docs/plans/issue-100-people-graph-person-context-implementation-plan.md
docs/plans/issue-110-forward-explicit-architecture.md
docs/plans/issue-110-forward-explicit-implementation-plan.md
docs/plans/issue-115-reply-to-message-implementation-journal.md
docs/plans/issue-115-reply-to-message-plan.md
docs/plans/mention-without-handle-plan.md
docs/plans/mention-without-handle-review-sol.md
docs/plans/nested-requests-architecture.md
docs/plans/nested-requests-cleanup-fk-manifest.json
docs/plans/nested-requests-implementation-plan.md
docs/plans/post-request-evaluation-detail-sheet-implementation-journal.md
docs/plans/post-request-evaluation-detail-sheet-plan.md
docs/plans/received-reviews-trust-changes-plan.md
docs/plans/request-threads-architecture.md
docs/plans/request-threads-implementation-plan.md
docs/plans/subjective-help-tag-evidence-architecture.md
docs/plans/subjective-help-tag-evidence-implementation-plan.md
graph-ego-neighbors-layout-issue.md
key.fb
out.key
product_testing_compact_buglist.md
product_testing_detailed_report.md
reports/
tg_style_research.md
```

**Ours to commit:** `docs/plans/request-detail-now-chat-people-plan.md`, this journal, and the source/test/doc files each unit owns. Everything else in that list stays untracked and untouched. `key.fb` / `out.key` are key material — never read, move, or commit them.

---

## Overseer decisions (binding; supersede plan prose where noted)

**OD-1 — Test migration lands with the deletion that breaks it.**
Plan §5 promises "each unit leaves the tree compiling", but §8 defers all test migration to U12. These contradict: U6 deletes `threads_list.dart` and `item_card.dart`, which are referenced by `threads_list_test.dart`, `item_card_golden_test.dart`, `promise_composer_live_wiring_test.dart`, `beacon_hierarchy_view_test.dart`. Dart will not compile the test tree, so `flutter test` cannot be green at U6.

Resolution: **migrating an existing test is part of the unit that breaks it.** U12 covers only the *new* T1–T10 suites. The per-unit table below assigns the existing tests explicitly. Plan intent (green increments) is preserved; plan letter (§8 all in U12) is not.

**OD-2 — Green bar is measured against the recorded baseline**, not against zero. Baseline results are recorded below. A worker may not "fix" a pre-existing failure outside its unit; report it in FINDINGS instead.

**OD-3 — Do not edit generated files.** `*.g.dart`, `*.freezed.dart`, `*.gr.dart`, `*.config.dart`, `*.schema.dart`, and `lib/ui/l10n/l10n*.dart` are outputs. Change the source (`.arb`, route definitions, annotations) and run codegen. `root_router.gr.dart` regenerates via `dart run build_runner build -d`; l10n via `flutter gen-l10n`.

**OD-4 — No push, no PR, no branch force-update.** Commits stay local on `feat/request-detail-now-chat-people`.

**OD-5 — Two manifest adjustments.**
(a) **U2 is folded into U4.** U2 is a pure additive declaration (`BeaconSurface` enum + `beaconVisibleSurfaces`) with no behaviour of its own; its only acceptance criterion is "it compiles", and U4 is its first consumer. A separate worker session for ~15 lines is waste. U4's review covers both.
(b) **`BeaconRoomLease` lives in `ui/util/`, not `ui/widget/`.** Plan §4.4 filed it under `ui/widget/`, but it is a plain controller class, not a widget, and this repo already keeps non-widget UI helpers in `features/beacon_view/ui/util/` (`beacon_hud_derivation.dart`, `beacon_closure_readiness.dart`, `beacon_accordion_sections.dart`).

---

## Baseline (recorded before any worker ran)

| Check | Command | Result |
|---|---|---|
| analyze | `cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos` | exit 0 — **0 errors, 89 warnings, 1365 infos** (1454 issues) |
| unit tests | `cd packages/client && flutter test` | exit 0 — **+2670 passed, ~34 skipped, 0 failed** (2m41s) |
| custom lints | `bash scripts/check-custom-lints.sh packages/client` | exit 0 — **total 32** (baseline 32): 22 `no_raw_edge_insets`, 10 `no_raw_border_radius` |

**Green bar for every unit:** analyze must stay at 0 errors and must not add warnings in touched files; `flutter test` must stay at 0 failures; custom lints must stay at 32.

> Correction: the custom-lint script takes a package argument — `bash scripts/check-custom-lints.sh packages/client`. Bare invocation exits 1 with a usage error. The "115" figure carried in earlier sessions is stale; the real client total is **32**.

---

## Unit manifest

Order is the plan's §5 order (dependency-aware; it was already reordered in rev 2 so no deletion precedes the removal of its last caller). One fresh worker per unit.

| # | Unit | Plan § | Existing tests this unit must also migrate (OD-1) | Status |
|---|---|---|---|---|
| U1 | Design-system tab support (`compactIconTabs`, `tabCompactWidth`, 48 dp min height) | §4.2 | `test/design_system/tentura_underline_tabs_test.dart` (must stay green unchanged) | complete |
| U2 | `BeaconSurface` enum + `beaconVisibleSurfaces`, added alongside old constants | §4.1 | none | **folded into U4** (OD-5) |
| U3 | `BeaconRoomLease` refcount + `ThreadHostCubit` guard tightening | §4.5 | `thread_host_cubit_test.dart` | pending |
| U4 | Four surface widgets (NOW / ROOM / PEOPLE / tabs), not yet wired | §4.4 | none | pending |
| U5 | `ThreadDetailGeneralTitle.onFacePileTap` + drop `ExcludeSemantics` | §3.1 | `thread_detail_test.dart` (title assertions) | pending |
| U6 | Screen recomposition; delete `beacon_operational_scroll_view.dart`, `threads_list.dart`, `item_card.dart` | §4.1, §4.3, §4.6 | `threads_list_test.dart` + `item_card_golden_test.dart` (+4 goldens) **delete**; `promise_composer_live_wiring_test.dart`, `beacon_hierarchy_view_test.dart`, `beacon_tab_reselect_folds_test.dart`, `beacon_operational_scroll_view_pinned_facts_test.dart`, `beacon_view_room_split_contract_test.dart` **migrate** | pending |
| U7 | l10n keys (`labelBeaconTabNow`, `labelBeaconTabChat`; remove `labelBeaconTabDiscussion`) | §7 | `test/l10n/request_terminology_contract_test.dart` | pending |
| U8 | Activity sheet + overflow entry | §4.7 | `activity_list_padding_test.dart` | pending |
| U9 | Anchor navigation off `ThreadDetailRoute` in `coordination_room_navigation.dart`, `room_message_tile.dart` | §4.8 | `room_message_tile_coordination_test.dart` | pending |
| U10 | Routing + deep links + `build_runner`; fold away `ThreadDetailScreen` | §4.6, §6, §6.1 | `request_thread_routing_test.dart`, `nested_beacon_navigation_test.dart`, `thread_detail_test.dart`, `request_threads_adaptive_test.dart`, `integration_test/*` | pending |
| U11 | Docs, rules, client semver bump + web cache-buster | §9 | doc-drift script | pending |
| U12 | New suites T1–T10 | §8 | — | pending |

---

## Verification matrix (plan §8 gates)

```bash
cd packages/client && flutter gen-l10n
cd packages/client && dart run build_runner build -d      # after U10
cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos
bash scripts/check-custom-lints.sh packages/client   # total 32 — must not grow
cd packages/client && flutter test
bash scripts/check-user-facing-terminology.sh
bash scripts/check-doc-drift.sh
cd packages/client && dart run tool/verify_web_version_consistency.dart
./scripts/run_client_integration_web_local.sh    # T7 web leg (final integration only)
```

---

## Open questions / blockers

- none yet

---

## Worker log

<!-- Workers append below. Newest last. Format:
### [UNIT] <status> — <ISO timestamp>
COMMITS / TESTS / FILES / FINDINGS / REMAINING
-->

### [overseer] scope established — 2026-09-07
Branch created off `main` at `40fd7bae1`. `cursor-agent` 2026.09.02, authenticated, `composer-2.5` present (non-fast). Baselines launched. OD-1..OD-4 recorded above.

### [U1] complete — 2026-09-07T20:15:00Z
COMMITS: 215424fd5 feat(design-system): add tabCompactWidth token for compact icon tabs; a1dc34e2a feat(design-system): add compactIconTabs layout to TenturaUnderlineTabs; d77ffc00f fix(design-system): enforce 48dp minimum tap target on underline tab cells; 9fcbe2229 test(design-system): cover compactIconTabs and 48dp tab hit targets
TESTS: `cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos` → exit 0, 0 errors, 89 warnings; `cd packages/client && flutter test test/design_system/tentura_underline_tabs_test.dart` → +17 passed, 0 failed; `cd packages/client && flutter test test/features/friends test/features/updates` → +85 passed, 0 failed
FILES: packages/client/lib/design_system/tentura_spacing.dart, packages/client/lib/design_system/tentura_tokens.dart, packages/client/lib/design_system/components/tentura_underline_tabs.dart, packages/client/test/design_system/tentura_underline_tabs_test.dart
FINDINGS: none — all 9 pre-existing underline-tabs tests pass unchanged; `compactIconTabs` defaults to `{}` so friends/updates call sites need no edits
REMAINING: none
