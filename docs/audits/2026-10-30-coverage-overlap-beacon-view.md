# Audit T2: Beacon view test coverage overlap

**Date:** 2026-10-30  
**Issue:** Refs [#851](https://github.com/Intersubjective/tentura/issues/851)  
**Scope:** `packages/client/test/features/beacon_view/**/_test.dart` (excluding `bench/`; no files in this directory carry a `pg` tag).

This audit measures **line coverage overlap** between beacon_view feature tests. No tests were changed. Identical covered lines do not imply redundant assertions; the Top 20 section includes manual read recommendations.

---

## Method

### Setup (once)

```bash
cd packages/client
flutter pub get
flutter gen-l10n
dart run build_runner build -d
flutter analyze lib test   # baseline before/after; docs-only commit
```

Coverage output directory (removed after the report):

```bash
mkdir -p /run/user/1000/cov851
```

### Per-file coverage (strictly serial)

Manifest: **169** `*_test.dart` files under `test/features/beacon_view/` (no `bench/` subtree; no `@Tags(['pg', …])` in this folder).

For each file `F`, slug = path with `/` → `__` (extension `.dart` kept in slug via `tr '/.' '__'`):

```bash
cd packages/client
../../scripts/run_with_test_cleanup.sh --timeout 15m -- \
  flutter test \
    --coverage \
    --coverage-path=/run/user/1000/cov851/<slug>.info \
    --dart-define=ENV=test \
    --dart-define-from-file=env/test.env \
    <F>
```

Runs were driven by a local batch script (`/tmp/cov851_run_all.sh`, not committed) that skipped already-measured files on resume. Pass/fail and duration were appended to `/tmp/cov851_results.jsonl`. Each `flutter test` was queued behind other machine-wide test runs via `scripts/run_with_test_cleanup.sh`; long queue waits were normal.

Detached supervision used `scripts/test_job.sh` with `TENTURA_TEST_JOB_ABANDON=12h` and periodic `test_job wait` so the batch was not killed as abandoned.

### Parsing and metrics

Local script `/tmp/cov851_analyze.py` (not committed) parsed each lcov record into `(source file, line)` pairs, keeping only paths under `lib/` and excluding:

- `*.g.dart`, `*.freezed.dart`, `*.gr.dart`
- `lib/ui/l10n/`
- `_g/` (generated GraphQL)

| Metric | Definition |
| --- | --- |
| **Subsumed** | File A is subsumed by B when every line A covers is also covered by B (`A ⊂ B`, `A ≠ B`). |
| **Near-duplicate** | Pairs with Jaccard ≥ 0.9 on covered line sets, excluding subset pairs. |
| **Unique contribution** | Lines covered by A that no other beacon_view test file covers. |
| **Greedy set cover** | Repeatedly keep the file covering the most still-uncovered lines until the union is covered; reports **size** of that set (optimistic w.r.t. behaviour). |

---

## Summary

| Measure | Value |
| --- | ---: |
| Files measured | 169 |
| Files failed | 0 |
| Distinct `(lib file, line)` pairs covered by ≥1 test | **17,450** |
| Greedy minimal set size (line coverage only) | **131** |
| Subsumed files | 20 |
| Near-duplicate pairs (J ≥ 0.9) | 94 |
| Files with unique contribution < 5 lines (non-zero total) | 70 |
| Sum of per-file durations | **9485 s** (2h 38m 5s) |
| Wall clock (batch jobs, incl. queue) | ~**2h 40m** (first job abandoned at 67/169 after 45m without wait; resumed to completion) |

**Interpretation:** 169 files collapse to ~131 for *line* coverage alone, but beacon_view tests heavily share `beacon_view_screen_harness.dart`, cubit harnesses, and full-screen pumps — so **94** near-duplicate pairs and **20** subsumed files mostly reflect shared scaffolding, not duplicate assertions. Low unique line count often means the file asserts a narrow regression (#NNN) while reusing the same widget tree as siblings.

---

## Failed runs

None (all 169 exited 0).

---

## Subsumed test files (A ⊆ B)

Count: **20** files whose entire `lib/` line set is covered by at least one other beacon_view test file.

| Subsumed file | Lines covered | Superset file(s) |
| --- | --- | --- |
| beacon_closure_assigned_role_settled_test.dart | 0 | beacon_hud_author_action_test.dart |
| beacon_helper_hud_wrap_up_test.dart | 0 | request_route_open_round_trips_test.dart |
| beacon_scope_stale_listener_test.dart | 0 | request_route_open_round_trips_test.dart |
| beacon_view_case_mark_people_seen_test.dart | 0 | help_offer_tile_sheet_shared_chat_hint_test.dart, help_offer_tile_sheet_backup_actions_test.dart, issue_734_action_confirmations_test.dart, beacon_view_cubit_people_seen_test.dart (+2) |
| beacon_view_cubit_room_seen_peer_test.dart | 0 | beacon_view_cubit_fact_invalidation_test.dart, issue_157_plan_live_sync_test.dart |
| beacon_view_forward_viewer_can_forward_test.dart | 0 | beacon_showcase_snack_bar_clears_actions_test.dart, issue_492_room_header_same_on_every_tab_test.dart, author_decline_status_phone_legibility_test.dart, issue_733_showcase_final_check_notice_test.dart (+28) |
| beacon_view_home_rail_test.dart | 0 | author_decline_status_phone_legibility_test.dart, issue_168_duplicate_overflow_menus_test.dart, beacon_message_canonicalizer_test.dart, beacon_split_now_pane_resize_test.dart (+1) |
| beacon_view_surface_for_tab_test.dart | 0 | beacon_showcase_snack_bar_clears_actions_test.dart, issue_492_room_header_same_on_every_tab_test.dart, author_decline_status_phone_legibility_test.dart, issue_733_showcase_final_check_notice_test.dart (+23) |
| closed_request_banner_test.dart | 0 | beacon_operational_header_closure_result_card_test.dart, issue_758_left_helper_result_card_test.dart, beacon_operational_header_card_test.dart |
| help_offer_author_seen_initial_query_test.dart | 0 | help_offer_author_seen_test.dart |
| help_offer_tile_admission_semantics_test.dart | 0 | help_offer_tile_type_chip_test.dart, request_people_add_to_tag_test.dart, beacon_people_tab_test.dart |
| issue_168_duplicate_overflow_menus_test.dart | 0 | beacon_message_canonicalizer_test.dart, beacon_back_navigation_test.dart |
| issue_380_final_check_line_semantics_test.dart | 0 | issue_380_extend_final_check_visible_test.dart |
| issue_492_room_header_same_on_every_tab_test.dart | 0 | beacon_back_navigation_test.dart |
| issue_496_viewer_trail_once_test.dart | 0 | beacon_people_tab_test.dart |
| issue_527_overflow_withdraw_test.dart | 0 | issue_527_offer_pending_showcase_test.dart |
| issue_692_update_plan_blank_save_test.dart | 0 | b085_now_line_edit_conflict_test.dart, next_step_code_unit_limit_test.dart |
| issue_862_current_line_save_focus_test.dart | 0 | next_step_save_error_in_sheet_test.dart, b085_now_line_edit_conflict_test.dart, next_step_code_unit_limit_test.dart |
| tentura_avatar_overlay_test.dart | 0 | b077_people_tab_offer_accepted_test.dart |
| u093_team_presence_watch_test.dart | 0 | beacon_view_cubit_people_seen_patch_test.dart, beacon_view_cubit_people_seen_test.dart, help_offer_author_seen_test.dart |

---

## Near-duplicate pairs (Jaccard ≥ 0.9, not subset)

Showing top **35** of **94** pairs by Jaccard.

| File A | File B | Jaccard | ∩ lines | |A| | |B| |
| --- | --- | --- | --- | --- | --- |
| beacon_split_now_pane_resize_test.dart | issue_168_duplicate_overflow_menus_test.dart | 0.9935 | 3365 | 3386 | 3366 |
| beacon_view_harness_status_sync_test.dart | beacon_view_home_rail_test.dart | 0.9887 | 3324 | 3340 | 3346 |
| help_offer_author_seen_mapping_test.dart | timeline_help_offer_mapping_test.dart | 0.9836 | 420 | 421 | 426 |
| beacon_view_harness_status_sync_test.dart | issue_168_duplicate_overflow_menus_test.dart | 0.9829 | 3324 | 3340 | 3366 |
| help_offer_author_seen_initial_query_test.dart | help_offer_author_seen_l10n_test.dart | 0.9775 | 1783 | 1802 | 1805 |
| beacon_split_now_pane_resize_test.dart | beacon_view_harness_status_sync_test.dart | 0.9771 | 3324 | 3386 | 3340 |
| author_decline_status_phone_legibility_test.dart | issue_168_duplicate_overflow_menus_test.dart | 0.9768 | 3365 | 3444 | 3366 |
| issue_169_discussion_cropped_test.dart | issue_451_now_shown_once_test.dart | 0.9766 | 4332 | 4381 | 4387 |
| beacon_view_forward_viewer_can_forward_test.dart | beacon_view_surface_for_tab_test.dart | 0.9721 | 383 | 387 | 390 |
| author_decline_status_phone_legibility_test.dart | beacon_split_now_pane_resize_test.dart | 0.9711 | 3365 | 3444 | 3386 |
| issue_169_discussion_cropped_test.dart | issue_415_room_focus_order_test.dart | 0.9662 | 4350 | 4381 | 4471 |
| beacon_accordion_sections_test.dart | beacon_view_forward_viewer_can_forward_test.dart | 0.9623 | 383 | 394 | 387 |
| author_decline_status_phone_legibility_test.dart | beacon_view_harness_status_sync_test.dart | 0.9607 | 3324 | 3444 | 3340 |
| beacon_view_case_mark_people_seen_test.dart | beacon_view_forward_viewer_can_forward_test.dart | 0.9599 | 383 | 395 | 387 |
| beacon_accordion_sections_test.dart | beacon_view_surface_for_tab_test.dart | 0.9551 | 383 | 394 | 390 |
| beacon_view_forward_viewer_can_forward_test.dart | beacon_view_room_write_actions_test.dart | 0.9551 | 383 | 387 | 397 |
| beacon_view_cubit_room_seen_peer_test.dart | beacon_view_you_responsibility_test.dart | 0.9543 | 689 | 701 | 710 |
| issue_415_room_focus_order_test.dart | issue_451_now_shown_once_test.dart | 0.9541 | 4325 | 4471 | 4387 |
| beacon_view_case_mark_people_seen_test.dart | beacon_view_surface_for_tab_test.dart | 0.9527 | 383 | 395 | 390 |
| beacon_view_forward_viewer_can_forward_test.dart | help_offer_author_seen_gql_test.dart | 0.9504 | 383 | 387 | 399 |
| beacon_view_cubit_room_host_test.dart | beacon_view_cubit_room_seen_peer_test.dart | 0.9490 | 689 | 714 | 701 |
| b079_now_line_partial_refresh_test.dart | beacon_view_cubit_hint_burst_test.dart | 0.9489 | 724 | 748 | 739 |
| beacon_view_room_write_actions_test.dart | beacon_view_surface_for_tab_test.dart | 0.9480 | 383 | 397 | 390 |
| beacon_view_cubit_hint_burst_test.dart | beacon_view_cubit_room_seen_peer_test.dart | 0.9459 | 700 | 739 | 701 |
| b079_now_line_partial_refresh_test.dart | issue_157_plan_live_sync_test.dart | 0.9442 | 744 | 748 | 784 |
| beacon_accordion_sections_test.dart | beacon_view_case_mark_people_seen_test.dart | 0.9433 | 383 | 394 | 395 |
| beacon_view_surface_for_tab_test.dart | help_offer_author_seen_gql_test.dart | 0.9433 | 383 | 390 | 399 |
| beacon_showcase_questions_entry_test.dart | beacon_showcase_snack_bar_clears_actions_test.dart | 0.9422 | 2054 | 2133 | 2101 |
| beacon_status_sheet_close_test.dart | issue_475_status_sheet_no_draft_row_test.dart | 0.9408 | 1271 | 1309 | 1313 |
| beacon_view_forward_viewer_can_forward_test.dart | beacon_view_room_admission_test.dart | 0.9390 | 385 | 387 | 408 |
| beacon_accordion_sections_test.dart | beacon_view_room_write_actions_test.dart | 0.9387 | 383 | 394 | 397 |
| beacon_view_cubit_room_seen_peer_test.dart | issue_724_access_parent_load_test.dart | 0.9387 | 689 | 701 | 722 |
| beacon_view_block_marker_test.dart | beacon_view_cubit_hint_burst_test.dart | 0.9381 | 712 | 732 | 739 |
| beacon_view_cubit_room_host_test.dart | beacon_view_you_responsibility_test.dart | 0.9374 | 689 | 714 | 710 |
| help_offer_tile_admission_semantics_test.dart | issue_416_people_tab_avatar_test.dart | 0.9369 | 921 | 970 | 934 |

---

## Low unique contribution (< 5 lines)

Files with fewer than five `lib/` lines not covered by any other beacon_view test (excluding files with zero coverage).

| File | Unique lines | Total lines |
| --- | --- | --- |
| activity_list_padding_test.dart | 0 | 793 |
| beacon_closure_assigned_role_settled_test.dart | 0 | 492 |
| beacon_helper_hud_wrap_up_test.dart | 0 | 412 |
| beacon_hud_author_act_block_test.dart | 0 | 699 |
| beacon_scope_stale_listener_test.dart | 0 | 427 |
| beacon_showcase_questions_entry_test.dart | 0 | 2133 |
| beacon_tab_reselect_folds_test.dart | 0 | 1803 |
| beacon_view_case_mark_people_seen_test.dart | 0 | 395 |
| beacon_view_cubit_hint_burst_test.dart | 0 | 739 |
| beacon_view_cubit_room_seen_peer_test.dart | 0 | 701 |
| beacon_view_first_load_latch_test.dart | 0 | 747 |
| beacon_view_forward_viewer_can_forward_test.dart | 0 | 387 |
| beacon_view_harness_status_sync_test.dart | 0 | 3340 |
| beacon_view_home_rail_test.dart | 0 | 3346 |
| beacon_view_status_bottom_sheet_test.dart | 0 | 734 |
| beacon_view_surface_for_tab_test.dart | 0 | 390 |
| closed_request_banner_test.dart | 0 | 715 |
| help_offer_author_seen_initial_query_test.dart | 0 | 1802 |
| help_offer_author_seen_mapping_test.dart | 0 | 421 |
| help_offer_tile_admission_semantics_test.dart | 0 | 970 |
| help_offer_tile_sheet_shared_chat_hint_test.dart | 0 | 1244 |
| issue_149_header_status_live_sync_test.dart | 0 | 878 |
| issue_168_duplicate_overflow_menus_test.dart | 0 | 3366 |
| issue_380_final_check_line_semantics_test.dart | 0 | 737 |
| issue_451_now_shown_once_test.dart | 0 | 4387 |
| issue_492_room_header_same_on_every_tab_test.dart | 0 | 3566 |
| issue_496_viewer_trail_once_test.dart | 0 | 448 |
| issue_527_overflow_withdraw_test.dart | 0 | 419 |
| issue_532_hud_plan_pending_tick_test.dart | 0 | 1398 |
| issue_609_now_line_wide_people_test.dart | 0 | 4936 |
| issue_684_offer_help_double_tap_test.dart | 0 | 1042 |
| issue_692_update_plan_blank_save_test.dart | 0 | 893 |
| issue_724_access_parent_load_test.dart | 0 | 722 |
| issue_804_add_plan_hides_on_close_test.dart | 0 | 2428 |
| issue_862_current_line_save_focus_test.dart | 0 | 756 |
| request_declined_forwards_first_load_test.dart | 0 | 3855 |
| request_screen_open_round_trips_test.dart | 0 | 1616 |
| request_slow_empty_children_gate_test.dart | 0 | 2907 |
| tentura_avatar_overlay_test.dart | 0 | 674 |
| u093_team_presence_watch_test.dart | 0 | 667 |
| beacon_status_sheet_close_test.dart | 1 | 1309 |
| beacon_surface_tabs_360_labels_test.dart | 1 | 2493 |
| beacon_view_cubit_people_seen_patch_test.dart | 1 | 807 |
| beacon_view_cubit_people_seen_test.dart | 1 | 799 |
| beacon_view_forward_overflow_test.dart | 1 | 844 |

---

## Top 20 to merge or delete

Manual read of the highest-signal subsumed / near-duplicate candidates (coverage suggests overlap; recommendations are behavioural).

| Rank | Pair / file | Recommendation | Reason |
| ---: | --- | --- | --- |
| 1 | `help_offer_author_seen_initial_query_test.dart` ⊆ `help_offer_author_seen_test.dart` | **keep** | Initial-query `authorSeenAt` vs realtime `people_seen` flip and mark-seen calls are different delivery paths (#178). |
| 2 | `beacon_view_cubit_room_seen_peer_test.dart` ⊆ `beacon_view_cubit_fact_invalidation_test.dart` | **keep** | Same cubit harness, but asserts `roomSeenPeer` must not refetch beacon vs `factCard` targeted refresh (#617). |
| 3 | `issue_380_final_check_line_semantics_test.dart` ⊆ `issue_380_extend_final_check_visible_test.dart` | **keep** | Semantics node for the extensions hint line (#634) vs end-date/hud/log after extend (#380). |
| 4 | `closed_request_banner_test.dart` ⊆ `beacon_operational_header_closure_result_card_test.dart` | **keep** | Isolated `ClosedRequestBanner` widget vs full operational header + closure result card (q8s8). |
| 5 | `issue_527_overflow_withdraw_test.dart` ⊆ `issue_527_offer_pending_showcase_test.dart` | **keep** | Pure overflow predicate unit tests vs showcase widget copy/withdraw button (#527). |
| 6 | `beacon_view_home_rail_test.dart` ⊆ `author_decline_status_phone_legibility_test.dart` | **keep** | Field rail tab (#retired Updates) vs phone decline subtitle legibility (#486); shared harness lines only. |
| 7 | `help_offer_tile_admission_semantics_test.dart` ⊆ `help_offer_tile_type_chip_test.dart` | **keep** | Admission trail semantics vs type chip rendering on the tile. |
| 8 | `issue_168_duplicate_overflow_menus_test.dart` ⊆ `beacon_message_canonicalizer_test.dart` | **keep** | Overflow menu duplication regression vs message canonicalizer unit logic. |
| 9 | `issue_492_room_header_same_on_every_tab_test.dart` ⊆ `beacon_back_navigation_test.dart` | **keep** | Header parity across tabs vs back navigation stack behaviour. |
| 10 | `issue_496_viewer_trail_once_test.dart` ⊆ `beacon_people_tab_test.dart` | **keep** | Viewer trail shown once vs broader people tab coverage. |
| 11 | `beacon_view_forward_viewer_can_forward_test.dart` ⊆ `beacon_showcase_snack_bar_clears_actions_test.dart` | **keep** | Forward permission for viewer vs showcase snack-bar action clearing. |
| 12 | `beacon_view_surface_for_tab_test.dart` ⊆ `beacon_showcase_snack_bar_clears_actions_test.dart` | **keep** | Tab surface routing vs snack-bar lifecycle. |
| 13 | `beacon_closure_assigned_role_settled_test.dart` ⊆ `beacon_hud_author_action_test.dart` | **keep** | Closure role settled state vs author HUD actions. |
| 14 | `beacon_helper_hud_wrap_up_test.dart` / `beacon_scope_stale_listener_test.dart` ⊆ `request_route_open_round_trips_test.dart` | **keep** | Narrow HUD/scope tests vs route open round-trip integration harness. |
| 15 | `beacon_view_case_mark_people_seen_test.dart` ⊆ `help_offer_tile_sheet_shared_chat_hint_test.dart` | **keep** | Case-level mark-seen vs sheet shared-chat hint copy. |
| 16 | `issue_692_update_plan_blank_save_test.dart` ⊆ `b085_now_line_edit_conflict_test.dart` | **keep** | Plan blank-save guard vs now-line edit conflict (#692 vs b085). |
| 17 | `issue_862_current_line_save_focus_test.dart` ⊆ `next_step_save_error_in_sheet_test.dart` | **merge** (optional) | Both exercise next-step save error/focus in sheet; could fold #862 focus case into the sheet error test if assertions stay distinct. |
| 18 | `tentura_avatar_overlay_test.dart` ⊆ `b077_people_tab_offer_accepted_test.dart` | **keep** | Avatar overlay widget vs people-tab accepted-offer scenario. |
| 19 | `u093_team_presence_watch_test.dart` ⊆ `beacon_view_cubit_people_seen_patch_test.dart` | **keep** | Team presence watch tick vs cubit people_seen patch application. |
| 20 | `help_offer_author_seen_mapping_test.dart` ≈ `timeline_help_offer_mapping_test.dart` (J≈0.98) | **merge** | Both map coordination rows to timeline help-offer fields; combine mapping table tests in one file. |


---

## Greedy minimal set (reference)

Line-coverage-only set cover selected **131** files. Full list (for tooling) was written to `/tmp/cov851_analysis.json` during the audit run and is not committed.

---

## Cleanup

```bash
rm -rf /run/user/1000/cov851
```
