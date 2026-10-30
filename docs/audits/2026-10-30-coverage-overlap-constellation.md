# Audit T2: Constellation test coverage overlap

**Date:** 2026-10-30  
**Issue:** Refs [#838](https://github.com/Intersubjective/tentura/issues/838)  
**Scope:** `packages/client/test/features/constellation/**/_test.dart` (excluding `bench/` and files tagged `pg`; none of the constellation files carry a `pg` tag).

This audit measures **line coverage overlap** between constellation feature tests. No tests were changed. Identical covered lines do not imply redundant assertions; the Top 20 section includes manual read recommendations.

---

## Method

### Setup (once)

```bash
cd packages/client
flutter pub get
flutter gen-l10n
dart run build_runner build -d
flutter analyze   # baseline only; docs-only change in this PR
```

On this Cloud Agent VM, `scripts/run_with_test_cleanup.sh` requires a writable temp directory; runs used:

```bash
export TMPDIR=/tmp/tentura-test-tmp
mkdir -p "$TMPDIR" /tmp/cov
```

### Per-file coverage (serial)

Manifest: all `*_test.dart` under `test/features/constellation/`, excluding `bench/` and `@Tags(['pg', ...])` (**225 files**).

For each file `F`, with slug = path with `/` → `__` and `.dart` removed:

```bash
cd packages/client
../../scripts/run_with_test_cleanup.sh --timeout 15m -- \
  flutter test \
    --coverage \
    --coverage-path=/tmp/cov/<slug>.info \
    --dart-define=ENV=test \
    --dart-define-from-file=env/test.env \
    <F>
```

Pass/fail and wall duration were recorded per file (`/tmp/cov/run_results.jsonl`). Failed files were still attempted; see Failed runs below.

### Parsing and metrics

A local script (`/tmp/analyze_constellation_coverage.py`, not committed) parsed each lcov record into `(source file, line)` pairs, keeping only paths under `lib/` and excluding:

- `*.g.dart`, `*.freezed.dart`, `*.gr.dart`
- `lib/ui/l10n/`
- `_g/` (generated GraphQL)

Metrics:

| Metric | Definition |
| --- | --- |
| **Subsumed** | File A is subsumed by B when every line A covers is also covered by B (`A ⊂ B`, `A ≠ B`). |
| **Near-duplicate** | Pairs with Jaccard ≥ 0.9 on covered line sets, excluding subset pairs. |
| **Unique contribution** | Lines covered by A that no other constellation test file covers. |
| **Greedy set cover** | Repeatedly keep the file covering the most still-uncovered lines until the union is covered; reports **size** of that set (optimistic w.r.t. behaviour). |

---

## Summary

| Measure | Value |
| --- | ---: |
| Files measured | 225 |
| Files failed (still timed) | 2 |
| Distinct `(lib file, line)` pairs covered by ≥1 test | **18,915** |
| Greedy minimal set size (line coverage only) | **126** |
| Subsumed files | 27 |
| Near-duplicate pairs (J ≥ 0.9) | 192 |
| Files with unique contribution &lt; 5 lines | 141 |
| Total serial run time | **7094 s** (1h 58m 14s) |
| Sum of per-file durations | 7,092 s |

**Interpretation:** 225 files collapse to ~126 for *line* coverage alone, but many near-duplicates differ in **delivery path** (pointer vs web semantics), **issue regression** (#458, #640), or **fast domain** vs slow widget coverage. Low unique line count often means the file reuses the reference fixture and hits the same `ConstellationBody` paths as siblings while asserting different behaviour.

---

## Failed runs

| Test file | Duration (s) | lcov lines | Notes |
| --- | ---: | ---: | --- |
| `constellation_overlapping_dot_browser_touch_test.dart` | 7 | 0 | No coverage output |
| `constellation_timeline_spans_test.dart` | 47 | 364346 | Partial run before failure |

## Subsumed test files (A ⊆ B)

Count: **27** pairs where every `lib/` line hit by A is also hit by at least one other file.

| Subsumed file | Covered lines | Superset file(s) |
| --- | ---: | --- |
| `constellation_preview_reveals_node_test.dart` | 5241 | `constellation_body_test.dart` |
| `constellation_tag_magnet_label_avoidance_test.dart` | 4660 | `constellation_magnet_obstacle_clearance_test.dart` |
| `constellation_tag_lens_panel_test.dart` | 4428 | `constellation_tag_hull_layer_test.dart` |
| `constellation_reference_fixture_smoke_test.dart` | 4167 | `constellation_body_test.dart`, `constellation_camera_controls_test.dart`, `constellation_long_task_reporting_test.dart`, `constellation_node_position_rebuild_test.dart` (+3 more) |
| `constellation_overflow_group_test.dart` | 1757 | `constellation_camera_controls_test.dart` |
| `constellation_collapse_control_test.dart` | 1317 | `constellation_camera_controls_test.dart`, `constellation_overflow_group_rebuild_test.dart` |
| `constellation_realtime_refresh_test.dart` | 1243 | `constellation_lazy_refresh_staleness_window_test.dart` |
| `constellation_peer_profile_edge_lookup_test.dart` | 976 | `constellation_body_test.dart` |
| `constellation_layout_positions_pinned_test.dart` | 829 | `constellation_layout_test.dart` |
| `constellation_placement_batch_cap_test.dart` | 806 | `constellation_placement_failure_lifetime_test.dart` |
| `constellation_edge_style_test.dart` | 622 | `constellation_grew_from_edge_test.dart` |
| `constellation_edge_path_reuse_test.dart` | 472 | `constellation_edge_dash_path_build_count_test.dart` |
| `constellation_scene_composer_pinned_person_placement_test.dart` | 462 | `constellation_composer_person_drop_test.dart`, `constellation_composing_phase_test.dart` |
| `constellation_edge_painter_test.dart` | 448 | `constellation_semantic_edge_id_test.dart` |
| `radius_recipient_selection_test.dart` | 435 | `constellation_composer_cubit_test.dart`, `constellation_composer_sheet_test.dart` |
| `constellation_drag_cluster_parent_bounds_test.dart` | 427 | `constellation_drag_cluster_test.dart`, `constellation_group_drag_test.dart`, `constellation_node_drag_while_write_pending_test.dart`, `constellation_overflow_chips_placement_ack_test.dart` (+5 more) |
| `constellation_edge_stroke_draw_calls_test.dart` | 417 | `constellation_grew_from_edge_test.dart` |
| `constellation_minimap_projection_test.dart` | 411 | `constellation_minimap_widget_test.dart` |
| `constellation_density_test.dart` | 400 | `constellation_anchor_interaction_test.dart`, `constellation_app_bar_people_tags_entry_test.dart`, `constellation_app_bar_test.dart`, `constellation_body_test.dart` (+82 more) |
| `constellation_gather_test.dart` | 399 | `constellation_gather_batch_test.dart`, `constellation_layout_history_sheet_test.dart` |
| `synthetic_field_test.dart` | 398 | `constellation_multi_select_test.dart`, `constellation_placement_marker_body_test.dart` |
| `spatial_index_test.dart` | 396 | `grid_index_equivalence_test.dart` |
| `constellation_zoom_level_controller_test.dart` | 393 | `constellation_settled_label_set_test.dart` |
| `constellation_member_webs_case_test.dart` | 386 | `constellation_request_member_selection_test.dart`, `constellation_request_webs_test.dart` |
| `constellation_communities_test.dart` | 381 | `constellation_anchor_interaction_test.dart`, `constellation_anchors_apply_wire_test.dart`, `constellation_app_bar_people_tags_entry_test.dart`, `constellation_app_bar_test.dart` (+208 more) |
| `placement_outbox_entities_test.dart` | 381 | `constellation_anchor_interaction_test.dart`, `constellation_anchors_apply_wire_test.dart`, `constellation_app_bar_people_tags_entry_test.dart`, `constellation_app_bar_test.dart` (+208 more) |
| `constellation_cap_policy_test.dart` | 49 | `constellation_p06_composition_layout_test.dart` |

## Near-duplicate pairs (Jaccard ≥ 0.9, not subset)

Count: **192** pairs.

| File A | File B | Jaccard | Intersection | Lines A | Lines B |
| --- | --- | ---: | ---: | ---: | ---: |
| `constellation_dense_cluster_touch_nearest_test.dart` | `constellation_dense_cluster_web_tap_test.dart` | 0.9970 | 4971 | 4977 | 4980 |
| `constellation_dense_cluster_touch_nearest_test.dart` | `constellation_touch_nearest_node_tap_test.dart` | 0.9938 | 4970 | 4977 | 4994 |
| `constellation_dense_cluster_web_tap_test.dart` | `constellation_touch_nearest_node_tap_test.dart` | 0.9912 | 4965 | 4980 | 4994 |
| `constellation_hidden_text_view_pin_work_test.dart` | `constellation_text_view_recompute_budget_test.dart` | 0.9788 | 5544 | 5657 | 5551 |
| `constellation_layout_job_test.dart` | `constellation_layout_positions_pinned_test.dart` | 0.9775 | 826 | 842 | 829 |
| `constellation_dense_cluster_touch_nearest_test.dart` | `constellation_overlapping_targets_click_test.dart` | 0.9747 | 4971 | 4977 | 5094 |
| `constellation_error_mapper_test.dart` | `constellation_member_webs_case_test.dart` | 0.9744 | 381 | 386 | 386 |
| `constellation_error_mapper_test.dart` | `constellation_tidy_move_trails_test.dart` | 0.9744 | 381 | 386 | 386 |
| `constellation_member_webs_case_test.dart` | `constellation_tidy_move_trails_test.dart` | 0.9744 | 381 | 386 | 386 |
| `constellation_remote_hint_delivery_pg_test.dart` | `constellation_remote_hint_freshness_test.dart` | 0.9741 | 902 | 909 | 919 |
| `constellation_overflow_group_rebuild_test.dart` | `constellation_request_spawn_test.dart` | 0.9738 | 4350 | 4395 | 4422 |
| `constellation_overlapping_targets_click_test.dart` | `constellation_touch_nearest_node_tap_test.dart` | 0.9722 | 4973 | 5094 | 4994 |
| `constellation_dense_cluster_web_tap_test.dart` | `constellation_overlapping_targets_click_test.dart` | 0.9722 | 4966 | 4980 | 5094 |
| `constellation_edge_style_test.dart` | `constellation_temporary_presence_style_test.dart` | 0.9699 | 613 | 622 | 623 |
| `constellation_error_mapper_test.dart` | `constellation_layout_geometry_test.dart` | 0.9695 | 381 | 386 | 388 |
| `constellation_layout_geometry_test.dart` | `constellation_member_webs_case_test.dart` | 0.9695 | 381 | 388 | 386 |
| `constellation_layout_geometry_test.dart` | `constellation_tidy_move_trails_test.dart` | 0.9695 | 381 | 388 | 386 |
| `constellation_render_cap_semantic_zoom_test.dart` | `constellation_tag_lens_cubit_test.dart` | 0.9639 | 1227 | 1233 | 1267 |
| `radius_recipient_selection_tag_test.dart` | `radius_recipient_selection_test.dart` | 0.9639 | 427 | 435 | 435 |
| `constellation_magnet_obstacle_clearance_test.dart` | `constellation_restored_magnet_clearance_test.dart` | 0.9634 | 4711 | 4734 | 4867 |
| `constellation_error_mapper_test.dart` | `constellation_zoom_level_test.dart` | 0.9621 | 381 | 386 | 391 |
| `constellation_member_webs_case_test.dart` | `constellation_zoom_level_test.dart` | 0.9621 | 381 | 386 | 391 |
| `constellation_zoom_level_test.dart` | `constellation_tidy_move_trails_test.dart` | 0.9621 | 381 | 391 | 386 |
| `constellation_zoom_level_controller_test.dart` | `constellation_zoom_level_test.dart` | 0.9600 | 384 | 393 | 391 |
| `constellation_error_mapper_test.dart` | `constellation_zoom_level_controller_test.dart` | 0.9573 | 381 | 386 | 393 |
| `constellation_layout_geometry_test.dart` | `constellation_zoom_level_test.dart` | 0.9573 | 381 | 388 | 391 |
| `constellation_member_webs_case_test.dart` | `constellation_zoom_level_controller_test.dart` | 0.9573 | 381 | 386 | 393 |
| `constellation_zoom_level_controller_test.dart` | `constellation_tidy_move_trails_test.dart` | 0.9573 | 381 | 393 | 386 |
| `constellation_error_mapper_test.dart` | `constellation_tidied_snack_bar_test.dart` | 0.9549 | 381 | 386 | 394 |
| `constellation_error_mapper_test.dart` | `scene_update_gate_test.dart` | 0.9549 | 381 | 386 | 394 |
| `constellation_member_webs_case_test.dart` | `constellation_tidied_snack_bar_test.dart` | 0.9549 | 381 | 386 | 394 |
| `constellation_member_webs_case_test.dart` | `scene_update_gate_test.dart` | 0.9549 | 381 | 386 | 394 |
| `constellation_tidied_snack_bar_test.dart` | `constellation_tidy_move_trails_test.dart` | 0.9549 | 381 | 394 | 386 |
| `constellation_tidy_move_trails_test.dart` | `scene_update_gate_test.dart` | 0.9549 | 381 | 386 | 394 |
| `constellation_layout_geometry_test.dart` | `constellation_zoom_level_controller_test.dart` | 0.9525 | 381 | 388 | 393 |
| `constellation_overflow_group_rebuild_test.dart` | `constellation_overlay_layout_transition_test.dart` | 0.9503 | 4300 | 4395 | 4430 |
| `constellation_error_mapper_test.dart` | `spatial_index_test.dart` | 0.9501 | 381 | 386 | 396 |
| `constellation_layout_geometry_test.dart` | `constellation_tidied_snack_bar_test.dart` | 0.9501 | 381 | 388 | 394 |
| `constellation_layout_geometry_test.dart` | `scene_update_gate_test.dart` | 0.9501 | 381 | 388 | 394 |
| `constellation_member_webs_case_test.dart` | `spatial_index_test.dart` | 0.9501 | 381 | 386 | 396 |
| `constellation_tidy_move_trails_test.dart` | `spatial_index_test.dart` | 0.9501 | 381 | 386 | 396 |
| `constellation_restored_magnet_clearance_test.dart` | `constellation_tag_magnet_label_avoidance_test.dart` | 0.9483 | 4637 | 4867 | 4660 |
| `constellation_placement_discard_unknown_test.dart` | `constellation_placement_retry_discard_test.dart` | 0.9460 | 859 | 873 | 894 |
| `constellation_error_mapper_test.dart` | `synthetic_field_test.dart` | 0.9454 | 381 | 386 | 398 |
| `constellation_layout_geometry_test.dart` | `spatial_index_test.dart` | 0.9454 | 381 | 388 | 396 |
| `constellation_member_webs_case_test.dart` | `synthetic_field_test.dart` | 0.9454 | 381 | 386 | 398 |
| `constellation_tidy_move_trails_test.dart` | `synthetic_field_test.dart` | 0.9454 | 381 | 386 | 398 |
| `constellation_long_task_reporting_test.dart` | `constellation_overflow_group_rebuild_test.dart` | 0.9440 | 4183 | 4219 | 4395 |
| `constellation_error_mapper_test.dart` | `constellation_gather_test.dart` | 0.9431 | 381 | 386 | 399 |
| `constellation_error_mapper_test.dart` | `constellation_tag_view_scope_test.dart` | 0.9431 | 381 | 386 | 399 |
| `constellation_gather_test.dart` | `constellation_member_webs_case_test.dart` | 0.9431 | 381 | 399 | 386 |
| `constellation_gather_test.dart` | `constellation_tidy_move_trails_test.dart` | 0.9431 | 381 | 399 | 386 |
| `constellation_member_webs_case_test.dart` | `constellation_tag_view_scope_test.dart` | 0.9431 | 381 | 386 | 399 |
| `constellation_tidied_snack_bar_test.dart` | `constellation_zoom_level_test.dart` | 0.9431 | 381 | 394 | 391 |
| `constellation_zoom_level_test.dart` | `scene_update_gate_test.dart` | 0.9431 | 381 | 391 | 394 |
| `constellation_tag_view_scope_test.dart` | `constellation_tidy_move_trails_test.dart` | 0.9431 | 381 | 399 | 386 |
| `constellation_tag_lens_forward_test.dart` | `constellation_tag_lens_panel_test.dart` | 0.9429 | 4410 | 4659 | 4428 |
| `constellation_overlay_layout_transition_test.dart` | `constellation_request_spawn_test.dart` | 0.9425 | 4295 | 4430 | 4422 |
| `constellation_placement_batch_cap_test.dart` | `constellation_placement_case_test.dart` | 0.9422 | 782 | 806 | 806 |
| `constellation_tag_filter_test.dart` | `constellation_tag_view_scope_test.dart` | 0.9420 | 390 | 405 | 399 |
| `constellation_density_test.dart` | `constellation_error_mapper_test.dart` | 0.9407 | 381 | 400 | 386 |
| `constellation_density_test.dart` | `constellation_member_webs_case_test.dart` | 0.9407 | 381 | 400 | 386 |
| `constellation_density_test.dart` | `constellation_tidy_move_trails_test.dart` | 0.9407 | 381 | 400 | 386 |
| `constellation_layout_geometry_test.dart` | `synthetic_field_test.dart` | 0.9407 | 381 | 388 | 398 |
| `constellation_drag_release_paths_test.dart` | `constellation_node_drag_while_write_pending_test.dart` | 0.9395 | 5034 | 5225 | 5167 |
| `constellation_tag_lens_panel_test.dart` | `constellation_tag_view_entry_visibility_test.dart` | 0.9394 | 4400 | 4428 | 4656 |
| `constellation_gather_test.dart` | `constellation_layout_geometry_test.dart` | 0.9384 | 381 | 399 | 388 |
| `constellation_layout_geometry_test.dart` | `constellation_tag_view_scope_test.dart` | 0.9384 | 381 | 388 | 399 |
| `constellation_tidied_snack_bar_test.dart` | `constellation_zoom_level_controller_test.dart` | 0.9384 | 381 | 394 | 393 |
| `constellation_zoom_level_controller_test.dart` | `scene_update_gate_test.dart` | 0.9384 | 381 | 393 | 394 |
| `constellation_zoom_level_test.dart` | `spatial_index_test.dart` | 0.9384 | 381 | 391 | 396 |
| `constellation_placement_ack_settlement_test.dart` | `constellation_placement_batch_cap_test.dart` | 0.9382 | 805 | 857 | 806 |
| `constellation_tag_lens_rendering_test.dart` | `constellation_trust_badge_test.dart` | 0.9379 | 3988 | 4151 | 4089 |
| `constellation_overlay_drag_rebuild_test.dart` | `constellation_overlay_layout_transition_test.dart` | 0.9376 | 4372 | 4605 | 4430 |
| `constellation_overflow_chip_clearance_test.dart` | `constellation_overflow_group_rebuild_test.dart` | 0.9373 | 4259 | 4408 | 4395 |
| `constellation_long_task_reporting_test.dart` | `constellation_request_spawn_test.dart` | 0.9366 | 4179 | 4219 | 4422 |
| `constellation_density_test.dart` | `constellation_layout_geometry_test.dart` | 0.9361 | 381 | 400 | 388 |
| `constellation_tidied_snack_bar_test.dart` | `scene_update_gate_test.dart` | 0.9361 | 381 | 394 | 394 |
| `constellation_placement_ack_settlement_test.dart` | `constellation_placement_case_test.dart` | 0.9360 | 804 | 857 | 806 |
| `constellation_composer_person_positions_do_not_recompose_test.dart` | `constellation_composer_request_pin_scope_test.dart` | 0.9356 | 4766 | 4937 | 4923 |
| `constellation_composer_drag_does_not_recompose_test.dart` | `constellation_composer_person_positions_do_not_recompose_test.dart` | 0.9353 | 4926 | 5256 | 4937 |
| `constellation_overflow_group_rebuild_test.dart` | `constellation_reference_fixture_smoke_test.dart` | 0.9349 | 4137 | 4395 | 4167 |
| `constellation_group_drag_test.dart` | `constellation_post_follows_author_test.dart` | 0.9348 | 5277 | 5364 | 5558 |
| `constellation_zoom_level_controller_test.dart` | `spatial_index_test.dart` | 0.9338 | 381 | 393 | 396 |
| `constellation_zoom_level_test.dart` | `synthetic_field_test.dart` | 0.9338 | 381 | 391 | 398 |
| `constellation_arrange_undo_shortcuts_test.dart` | `constellation_rearrange_everyone_test.dart` | 0.9316 | 4021 | 4142 | 4195 |
| `constellation_gather_test.dart` | `constellation_zoom_level_test.dart` | 0.9315 | 381 | 399 | 391 |
| `constellation_tidied_snack_bar_test.dart` | `spatial_index_test.dart` | 0.9315 | 381 | 394 | 396 |
| `constellation_zoom_level_test.dart` | `constellation_tag_view_scope_test.dart` | 0.9315 | 381 | 391 | 399 |
| `spatial_index_test.dart` | `scene_update_gate_test.dart` | 0.9315 | 381 | 396 | 394 |
| `constellation_trust_chain_line_presence_reason_test.dart` | `constellation_trust_chain_line_server_chain_test.dart` | 0.9308 | 4884 | 5211 | 4920 |
| `constellation_placement_ack_settlement_test.dart` | `constellation_placement_discard_unknown_test.dart` | 0.9308 | 834 | 857 | 873 |
| `constellation_post_label_test.dart` | `constellation_trust_badge_test.dart` | 0.9295 | 3878 | 3961 | 4089 |
| `constellation_mutual_trust_edges_test.dart` | `constellation_trust_chain_line_server_chain_test.dart` | 0.9293 | 4787 | 5018 | 4920 |
| `constellation_density_test.dart` | `constellation_zoom_level_test.dart` | 0.9293 | 381 | 400 | 391 |
| `constellation_error_mapper_test.dart` | `constellation_tag_filter_test.dart` | 0.9293 | 381 | 386 | 405 |
| `constellation_member_webs_case_test.dart` | `constellation_tag_filter_test.dart` | 0.9293 | 381 | 386 | 405 |
| `constellation_zoom_level_controller_test.dart` | `synthetic_field_test.dart` | 0.9293 | 381 | 393 | 398 |
| `constellation_tag_filter_test.dart` | `constellation_tidy_move_trails_test.dart` | 0.9293 | 381 | 405 | 386 |
| `constellation_preview_reveals_node_test.dart` | `constellation_selection_does_not_relayout_test.dart` | 0.9288 | 5047 | 5241 | 5240 |
| `constellation_node_drag_while_write_pending_test.dart` | `constellation_person_drag_with_pinned_requests_test.dart` | 0.9285 | 4842 | 5167 | 4890 |
| `constellation_field_store_anchor_coverage_test.dart` | `constellation_store_ack_merge_test.dart` | 0.9283 | 583 | 586 | 625 |
| `constellation_reference_fixture_smoke_test.dart` | `constellation_request_spawn_test.dart` | 0.9275 | 4133 | 4167 | 4422 |
| `constellation_collapse_control_test.dart` | `constellation_render_cap_semantic_zoom_test.dart` | 0.9274 | 1227 | 1317 | 1233 |
| `constellation_gather_test.dart` | `constellation_zoom_level_controller_test.dart` | 0.9270 | 381 | 399 | 393 |
| `constellation_tidied_snack_bar_test.dart` | `synthetic_field_test.dart` | 0.9270 | 381 | 394 | 398 |
| `constellation_zoom_level_controller_test.dart` | `constellation_tag_view_scope_test.dart` | 0.9270 | 381 | 393 | 399 |
| `synthetic_field_test.dart` | `scene_update_gate_test.dart` | 0.9270 | 381 | 398 | 394 |
| `constellation_placement_ack_settlement_test.dart` | `constellation_placement_failure_lifetime_test.dart` | 0.9256 | 833 | 857 | 876 |
| `constellation_layout_placement_invariants_test.dart` | `constellation_layout_positions_pinned_test.dart` | 0.9253 | 793 | 821 | 829 |
| `constellation_density_test.dart` | `constellation_zoom_level_controller_test.dart` | 0.9248 | 381 | 400 | 393 |
| `constellation_gather_test.dart` | `constellation_tidied_snack_bar_test.dart` | 0.9248 | 381 | 399 | 394 |
| `constellation_gather_test.dart` | `scene_update_gate_test.dart` | 0.9248 | 381 | 399 | 394 |
| `constellation_layout_geometry_test.dart` | `constellation_tag_filter_test.dart` | 0.9248 | 381 | 388 | 405 |
| `constellation_tidied_snack_bar_test.dart` | `constellation_tag_view_scope_test.dart` | 0.9248 | 381 | 394 | 399 |
| `constellation_tag_view_scope_test.dart` | `scene_update_gate_test.dart` | 0.9248 | 381 | 399 | 394 |
| `constellation_post_label_test.dart` | `constellation_tag_lens_rendering_test.dart` | 0.9241 | 3896 | 3961 | 4151 |
| `constellation_placement_arrangement_history_test.dart` | `constellation_placement_case_test.dart` | 0.9225 | 798 | 857 | 806 |
| `constellation_density_test.dart` | `constellation_tidied_snack_bar_test.dart` | 0.9225 | 381 | 400 | 394 |
| `constellation_density_test.dart` | `scene_update_gate_test.dart` | 0.9225 | 381 | 400 | 394 |
| `spatial_index_test.dart` | `synthetic_field_test.dart` | 0.9225 | 381 | 396 | 398 |
| `constellation_overflow_chip_clearance_test.dart` | `constellation_request_spawn_test.dart` | 0.9212 | 4234 | 4408 | 4422 |
| `constellation_own_drop_echo_coverage_test.dart` | `constellation_placement_case_test.dart` | 0.9211 | 782 | 825 | 806 |
| `constellation_edge_painter_test.dart` | `constellation_edge_path_reuse_test.dart` | 0.9207 | 441 | 448 | 472 |
| `constellation_gather_test.dart` | `spatial_index_test.dart` | 0.9203 | 381 | 399 | 396 |
| `constellation_tag_view_scope_test.dart` | `spatial_index_test.dart` | 0.9203 | 381 | 399 | 396 |
| `constellation_composer_cubit_tag_selection_test.dart` | `constellation_composer_publish_test.dart` | 0.9202 | 611 | 634 | 641 |
| `constellation_magnet_obstacle_clearance_test.dart` | `constellation_neighbour_overflow_reload_test.dart` | 0.9191 | 4466 | 4734 | 4591 |
| `constellation_magnet_obstacle_clearance_test.dart` | `constellation_tag_lens_forward_test.dart` | 0.9189 | 4498 | 4734 | 4659 |
| `constellation_label_placement_pan_cache_test.dart` | `constellation_long_task_reporting_test.dart` | 0.9189 | 4146 | 4439 | 4219 |
| `constellation_placement_batch_cap_test.dart` | `constellation_placement_discard_unknown_test.dart` | 0.9189 | 804 | 806 | 873 |
| `constellation_tag_magnets_test.dart` | `constellation_tag_view_entry_visibility_test.dart` | 0.9188 | 4594 | 4938 | 4656 |
| `constellation_own_drop_echo_coverage_test.dart` | `constellation_placement_batch_cap_test.dart` | 0.9188 | 781 | 825 | 806 |
| `constellation_density_test.dart` | `spatial_index_test.dart` | 0.9181 | 381 | 400 | 396 |
| `constellation_zoom_level_test.dart` | `constellation_tag_filter_test.dart` | 0.9181 | 381 | 391 | 405 |
| `constellation_collapse_control_test.dart` | `constellation_request_webs_test.dart` | 0.9170 | 1292 | 1317 | 1384 |
| `constellation_error_mapper_test.dart` | `constellation_minimap_projection_test.dart` | 0.9159 | 381 | 386 | 411 |
| `constellation_gather_test.dart` | `synthetic_field_test.dart` | 0.9159 | 381 | 399 | 398 |
| `constellation_member_webs_case_test.dart` | `constellation_minimap_projection_test.dart` | 0.9159 | 381 | 386 | 411 |
| `constellation_minimap_projection_test.dart` | `constellation_tidy_move_trails_test.dart` | 0.9159 | 381 | 411 | 386 |
| `constellation_tag_view_scope_test.dart` | `synthetic_field_test.dart` | 0.9159 | 381 | 399 | 398 |
| `constellation_person_drag_with_pinned_requests_test.dart` | `constellation_placement_marker_body_test.dart` | 0.9152 | 4837 | 4890 | 5232 |
| `constellation_overflow_chips_placement_ack_test.dart` | `constellation_placement_ack_layout_test.dart` | 0.9151 | 5531 | 5800 | 5775 |
| `constellation_long_task_reporting_test.dart` | `constellation_overlay_layout_transition_test.dart` | 0.9148 | 4132 | 4219 | 4430 |
| `constellation_drag_release_paths_test.dart` | `constellation_person_drag_with_pinned_requests_test.dart` | 0.9143 | 4831 | 5225 | 4890 |
| `constellation_density_test.dart` | `synthetic_field_test.dart` | 0.9137 | 381 | 400 | 398 |
| `constellation_gather_test.dart` | `constellation_tag_view_scope_test.dart` | 0.9137 | 381 | 399 | 399 |
| `constellation_zoom_level_controller_test.dart` | `constellation_tag_filter_test.dart` | 0.9137 | 381 | 393 | 405 |
| `constellation_neighbour_overflow_reload_test.dart` | `constellation_overflow_chip_clearance_test.dart` | 0.9126 | 4294 | 4591 | 4408 |
| `constellation_overflow_group_rebuild_test.dart` | `constellation_trust_badge_test.dart` | 0.9117 | 4046 | 4395 | 4089 |
| `constellation_placement_ack_settlement_test.dart` | `constellation_placement_retry_discard_test.dart` | 0.9116 | 835 | 857 | 894 |
| `constellation_density_test.dart` | `constellation_gather_test.dart` | 0.9115 | 381 | 400 | 399 |
| `constellation_density_test.dart` | `constellation_tag_view_scope_test.dart` | 0.9115 | 381 | 400 | 399 |
| `constellation_error_mapper_test.dart` | `constellation_tidy_offset_layer_test.dart` | 0.9115 | 381 | 386 | 413 |
| `constellation_layout_geometry_test.dart` | `constellation_minimap_projection_test.dart` | 0.9115 | 381 | 388 | 411 |
| `constellation_member_webs_case_test.dart` | `constellation_tidy_offset_layer_test.dart` | 0.9115 | 381 | 386 | 413 |
| `constellation_tidied_snack_bar_test.dart` | `constellation_tag_filter_test.dart` | 0.9115 | 381 | 394 | 405 |
| `constellation_tag_filter_test.dart` | `scene_update_gate_test.dart` | 0.9115 | 381 | 405 | 394 |
| `constellation_tidy_move_trails_test.dart` | `constellation_tidy_offset_layer_test.dart` | 0.9115 | 381 | 386 | 413 |
| `constellation_node_drag_while_write_pending_test.dart` | `constellation_placement_marker_body_test.dart` | 0.9109 | 4957 | 5167 | 5232 |
| `constellation_neighbour_overflow_reload_test.dart` | `constellation_restored_magnet_clearance_test.dart` | 0.9107 | 4508 | 4591 | 4867 |
| `constellation_label_placement_pan_cache_test.dart` | `constellation_reference_fixture_smoke_test.dart` | 0.9099 | 4100 | 4439 | 4167 |
| `constellation_overflow_group_rebuild_test.dart` | `constellation_overlay_drag_rebuild_test.dart` | 0.9092 | 4286 | 4395 | 4605 |
| `constellation_label_placement_pan_cache_test.dart` | `constellation_overflow_group_rebuild_test.dart` | 0.9092 | 4207 | 4439 | 4395 |
| `constellation_long_task_reporting_test.dart` | `constellation_overflow_chip_clearance_test.dart` | 0.9091 | 4108 | 4219 | 4408 |
| `constellation_hidden_label_hover_test.dart` | `constellation_overflow_group_rebuild_test.dart` | 0.9084 | 4284 | 4605 | 4395 |
| `constellation_collapse_control_test.dart` | `constellation_tag_lens_cubit_test.dart` | 0.9084 | 1230 | 1317 | 1267 |
| `constellation_tag_filter_test.dart` | `synthetic_field_test.dart` | 0.9074 | 382 | 405 | 398 |
| `constellation_layout_job_test.dart` | `constellation_layout_placement_invariants_test.dart` | 0.9071 | 791 | 842 | 821 |
| `constellation_layout_geometry_test.dart` | `constellation_tidy_offset_layer_test.dart` | 0.9071 | 381 | 388 | 413 |
| `constellation_tag_filter_test.dart` | `spatial_index_test.dart` | 0.9071 | 381 | 405 | 396 |
| `constellation_request_spawn_test.dart` | `constellation_trust_badge_test.dart` | 0.9062 | 4046 | 4422 | 4089 |
| `constellation_overlay_layout_transition_test.dart` | `constellation_reference_fixture_smoke_test.dart` | 0.9058 | 4086 | 4430 | 4167 |
| `constellation_hidden_label_hover_test.dart` | `constellation_overlay_layout_transition_test.dart` | 0.9057 | 4294 | 4605 | 4430 |
| `constellation_minimap_projection_test.dart` | `constellation_zoom_level_test.dart` | 0.9050 | 381 | 411 | 391 |
| `constellation_overlay_layout_transition_test.dart` | `constellation_trust_badge_test.dart` | 0.9045 | 4046 | 4430 | 4089 |
| `constellation_overlay_drag_rebuild_test.dart` | `constellation_request_spawn_test.dart` | 0.9044 | 4287 | 4605 | 4422 |
| `constellation_label_placement_pan_cache_test.dart` | `constellation_request_spawn_test.dart` | 0.9044 | 4208 | 4439 | 4422 |
| `constellation_neighbour_overflow_reload_test.dart` | `constellation_tag_magnet_label_avoidance_test.dart` | 0.9039 | 4392 | 4591 | 4660 |
| `constellation_tag_lens_forward_test.dart` | `constellation_tag_magnet_label_avoidance_test.dart` | 0.9038 | 4424 | 4659 | 4660 |
| `constellation_hidden_label_hover_test.dart` | `constellation_request_spawn_test.dart` | 0.9032 | 4284 | 4605 | 4422 |
| `constellation_edge_stroke_draw_calls_test.dart` | `constellation_error_mapper_test.dart` | 0.9028 | 381 | 417 | 386 |
| `constellation_edge_stroke_draw_calls_test.dart` | `constellation_member_webs_case_test.dart` | 0.9028 | 381 | 417 | 386 |
| `constellation_edge_stroke_draw_calls_test.dart` | `constellation_tidy_move_trails_test.dart` | 0.9028 | 381 | 417 | 386 |
| `constellation_tag_lens_panel_test.dart` | `constellation_tag_lens_rendering_test.dart` | 0.9022 | 4069 | 4428 | 4151 |
| `constellation_presence_rendering_widget_test.dart` | `constellation_tag_hull_layer_test.dart` | 0.9016 | 4829 | 5001 | 5184 |
| `constellation_gather_test.dart` | `constellation_tag_filter_test.dart` | 0.9007 | 381 | 399 | 405 |
| `constellation_minimap_projection_test.dart` | `constellation_zoom_level_controller_test.dart` | 0.9007 | 381 | 411 | 393 |
| `constellation_zoom_level_test.dart` | `constellation_tidy_offset_layer_test.dart` | 0.9007 | 381 | 391 | 413 |
| `constellation_overflow_chip_clearance_test.dart` | `constellation_overlay_layout_transition_test.dart` | 0.9002 | 4187 | 4408 | 4430 |
| `constellation_overflow_chip_clearance_test.dart` | `constellation_reference_fixture_smoke_test.dart` | 0.9001 | 4062 | 4408 | 4167 |
| `constellation_edge_dash_path_build_count_test.dart` | `constellation_edge_painter_test.dart` | 0.9000 | 441 | 483 | 448 |

## Low unique contribution (< 5 lines not covered elsewhere)

Count: **141** files.

| File | Unique lines | Total covered lines |
| --- | ---: | ---: |
| `constellation_cap_policy_test.dart` | 0 | 49 |
| `constellation_communities_test.dart` | 0 | 381 |
| `placement_outbox_entities_test.dart` | 0 | 381 |
| `constellation_member_webs_case_test.dart` | 0 | 386 |
| `constellation_zoom_level_test.dart` | 0 | 391 |
| `constellation_zoom_level_controller_test.dart` | 0 | 393 |
| `constellation_tidied_snack_bar_test.dart` | 0 | 394 |
| `spatial_index_test.dart` | 0 | 396 |
| `synthetic_field_test.dart` | 0 | 398 |
| `constellation_gather_test.dart` | 0 | 399 |
| `constellation_tag_view_scope_test.dart` | 0 | 399 |
| `constellation_density_test.dart` | 0 | 400 |
| `constellation_minimap_projection_test.dart` | 0 | 411 |
| `constellation_edge_stroke_draw_calls_test.dart` | 0 | 417 |
| `constellation_drag_cluster_parent_bounds_test.dart` | 0 | 427 |
| `radius_recipient_selection_tag_test.dart` | 0 | 435 |
| `radius_recipient_selection_test.dart` | 0 | 435 |
| `desired_anchor_projection_test.dart` | 0 | 442 |
| `constellation_edge_painter_test.dart` | 0 | 448 |
| `constellation_scene_composer_pinned_person_placement_test.dart` | 0 | 462 |
| `constellation_edge_path_reuse_test.dart` | 0 | 472 |
| `constellation_multi_selection_test.dart` | 0 | 490 |
| `constellation_zoom_level_frame_test.dart` | 0 | 514 |
| `constellation_presentation_frame_test.dart` | 0 | 598 |
| `constellation_composition_layout_node_spec_test.dart` | 0 | 606 |
| `constellation_edge_style_test.dart` | 0 | 622 |
| `constellation_temporary_presence_style_test.dart` | 0 | 623 |
| `constellation_store_ack_merge_test.dart` | 0 | 625 |
| `constellation_composer_cubit_tag_selection_test.dart` | 0 | 634 |
| `constellation_direct_contacts_composition_test.dart` | 0 | 655 |
| `constellation_placement_batch_cap_test.dart` | 0 | 806 |
| `constellation_placement_case_test.dart` | 0 | 806 |
| `constellation_layout_placement_invariants_test.dart` | 0 | 821 |
| `constellation_layout_positions_pinned_test.dart` | 0 | 829 |
| `constellation_layout_job_test.dart` | 0 | 842 |
| `constellation_placement_ack_settlement_test.dart` | 0 | 857 |
| `constellation_placement_discard_unknown_test.dart` | 0 | 873 |
| `constellation_layout_positional_stability_test.dart` | 0 | 902 |
| `constellation_pinned_person_outside_visible_set_test.dart` | 0 | 919 |
| `constellation_peer_profile_edge_lookup_test.dart` | 0 | 976 |
| `constellation_field_membership_v2_test.dart` | 0 | 1112 |
| `constellation_render_cap_semantic_zoom_test.dart` | 0 | 1233 |
| `constellation_realtime_refresh_test.dart` | 0 | 1243 |
| `constellation_lazy_refresh_staleness_window_test.dart` | 0 | 1244 |
| `constellation_tag_lens_cubit_test.dart` | 0 | 1267 |
| `constellation_single_compose_and_cached_preflight_test.dart` | 0 | 1290 |
| `constellation_collapse_control_test.dart` | 0 | 1317 |
| `constellation_cubit_composer_people_test.dart` | 0 | 1432 |
| `constellation_pinned_request_reload_test.dart` | 0 | 1457 |
| `constellation_server_trust_chain_cubit_test.dart` | 0 | 1481 |
| `constellation_temporary_presence_edge_test.dart` | 0 | 1656 |
| `constellation_placement_undoable_reset_test.dart` | 0 | 1683 |
| `constellation_overflow_group_test.dart` | 0 | 1757 |
| `constellation_composing_phase_test.dart` | 0 | 1782 |
| `constellation_select_toggle_test.dart` | 0 | 1910 |
| `constellation_nearest_ring_test.dart` | 0 | 3774 |
| `constellation_node_own_tag_glyphs_test.dart` | 0 | 3921 |
| `constellation_trust_badge_test.dart` | 0 | 4089 |
| `constellation_tag_lens_rendering_test.dart` | 0 | 4151 |
| `constellation_reference_fixture_smoke_test.dart` | 0 | 4167 |
| `constellation_overview_clusters_widget_test.dart` | 0 | 4255 |
| `constellation_scene_frozen_during_drag_test.dart` | 0 | 4278 |
| `constellation_overflow_collapse_test.dart` | 0 | 4287 |
| `constellation_composer_radius_test.dart` | 0 | 4299 |
| `constellation_overflow_group_rebuild_test.dart` | 0 | 4395 |
| `constellation_overflow_chip_clearance_test.dart` | 0 | 4408 |
| `constellation_request_spawn_test.dart` | 0 | 4422 |
| `constellation_tag_lens_panel_test.dart` | 0 | 4428 |
| `constellation_overlay_layout_transition_test.dart` | 0 | 4430 |
| `constellation_label_placement_pan_cache_test.dart` | 0 | 4439 |
| `constellation_composer_unplaced_candidates_test.dart` | 0 | 4504 |
| `constellation_gather_batch_test.dart` | 0 | 4537 |
| `constellation_hidden_label_hover_test.dart` | 0 | 4605 |
| `constellation_overlay_drag_rebuild_test.dart` | 0 | 4605 |
| `constellation_tag_magnet_label_avoidance_test.dart` | 0 | 4660 |
| `constellation_magnet_obstacle_clearance_test.dart` | 0 | 4734 |
| `constellation_placement_phase_node_rebuild_test.dart` | 0 | 4799 |
| `constellation_scene_revision_interaction_test.dart` | 0 | 4828 |
| `constellation_person_drag_with_pinned_requests_test.dart` | 0 | 4890 |
| `constellation_trust_chain_line_server_chain_test.dart` | 0 | 4920 |
| `constellation_composer_request_pin_scope_test.dart` | 0 | 4923 |
| `constellation_composer_person_positions_do_not_recompose_test.dart` | 0 | 4937 |
| `constellation_overview_cluster_staged_motion_test.dart` | 0 | 4959 |
| `constellation_box_selection_zoom_levels_test.dart` | 0 | 4976 |
| `constellation_dense_cluster_touch_nearest_test.dart` | 0 | 4977 |
| `constellation_dense_cluster_web_tap_test.dart` | 0 | 4980 |
| `constellation_node_drag_while_write_pending_test.dart` | 0 | 5167 |
| `constellation_tag_hull_layer_test.dart` | 0 | 5184 |
| `constellation_preview_reveals_node_test.dart` | 0 | 5241 |
| `constellation_overview_community_layout_test.dart` | 0 | 5274 |
| `constellation_zoom_level_wiring_test.dart` | 0 | 5275 |
| `constellation_edge_repaint_discipline_test.dart` | 0 | 5285 |
| `constellation_node_position_rebuild_test.dart` | 0 | 5410 |
| `constellation_settled_label_set_test.dart` | 0 | 5456 |
| `constellation_hidden_text_view_pin_work_test.dart` | 0 | 5657 |
| `constellation_placement_ack_layout_test.dart` | 0 | 5775 |
| `constellation_overflow_chips_placement_ack_test.dart` | 0 | 5800 |
| `constellation_overview_dots_widget_test.dart` | 0 | 5896 |
| `scene_update_gate_test.dart` | 1 | 394 |
| `constellation_post_expiry_mapping_test.dart` | 1 | 441 |
| `constellation_edge_dash_path_build_count_test.dart` | 1 | 483 |
| `constellation_sector_arrangement_test.dart` | 1 | 496 |
| `constellation_tidy_history_test.dart` | 1 | 512 |
| `constellation_tag_row_test.dart` | 1 | 688 |
| `constellation_own_drop_echo_coverage_test.dart` | 1 | 825 |
| `constellation_placement_arrangement_history_test.dart` | 1 | 857 |
| `constellation_remote_hint_delivery_pg_test.dart` | 1 | 909 |
| `constellation_request_member_selection_test.dart` | 1 | 1440 |
| `constellation_post_label_test.dart` | 1 | 3961 |
| `constellation_timeline_spans_test.dart` | 1 | 4839 |
| `constellation_district_level_widget_test.dart` | 1 | 4880 |
| `constellation_presence_rendering_widget_test.dart` | 1 | 5001 |
| `constellation_overflow_collapse_screen_test.dart` | 1 | 5102 |
| `constellation_trust_chain_line_presence_reason_test.dart` | 1 | 5211 |
| `constellation_group_drag_test.dart` | 1 | 5364 |
| `constellation_text_view_recompute_budget_test.dart` | 1 | 5551 |
| `constellation_post_follows_author_test.dart` | 1 | 5558 |
| `constellation_trust_chain_test.dart` | 2 | 438 |
| `constellation_scene_controller_test.dart` | 2 | 469 |
| `constellation_field_store_anchor_coverage_test.dart` | 2 | 586 |
| `constellation_low_zoom_hit_target_test.dart` | 2 | 940 |
| `constellation_arrange_menu_test.dart` | 2 | 2332 |
| `constellation_long_task_reporting_test.dart` | 2 | 4219 |
| `constellation_tag_view_entry_visibility_test.dart` | 2 | 4656 |
| `constellation_selection_does_not_relayout_test.dart` | 2 | 5240 |
| `constellation_pin_layout_compute_budget_test.dart` | 2 | 5951 |
| `constellation_arrangement_history_test.dart` | 3 | 431 |
| `constellation_placement_marker_test.dart` | 3 | 709 |
| `constellation_anchors_apply_wire_test.dart` | 3 | 768 |
| `constellation_label_budget_context_test.dart` | 3 | 1461 |
| `constellation_neighbour_overflow_reload_test.dart` | 3 | 4591 |
| `constellation_tag_lens_forward_test.dart` | 3 | 4659 |
| `constellation_cluster_staged_transition_test.dart` | 4 | 18 |
| `constellation_tidy_up_test.dart` | 4 | 467 |
| `constellation_field_store_retry_later_test.dart` | 4 | 535 |
| `constellation_field_store_case_test.dart` | 4 | 630 |
| `constellation_placement_retry_discard_test.dart` | 4 | 894 |
| `constellation_request_webs_test.dart` | 4 | 1384 |
| `constellation_arrange_undo_shortcuts_test.dart` | 4 | 4142 |
| `constellation_restored_magnet_clearance_test.dart` | 4 | 4867 |
| `constellation_scene_handoff_test.dart` | 4 | 5052 |

## Top 20 candidates to merge or delete

Manual read of the highest-signal subsumed / near-duplicate clusters. Recommendation is about test *maintenance*, not deleting coverage without moving assertions.

| # | Candidate(s) | Rec. | One-line reason |
| --- | --- | --- | --- |
| 1 | `constellation_reference_fixture_smoke_test.dart` | **delete** | Single smoke widget test only checks fixture layout positions; same paths exercised heavily by `constellation_body_test.dart` and others with stronger assertions. |
| 2 | `constellation_collapse_control_test.dart` | **merge** | One cubit-level toggle test; line set subsumed by `constellation_camera_controls_test.dart` / overflow rebuild tests—fold into overflow/camera group. |
| 3 | `constellation_overflow_group_test.dart` | **merge** | Isolated chip sizing widget test; coverage subsumed by camera controls—merge chip sizing case into that file. |
| 4 | `constellation_cap_policy_test.dart` | **merge** | Domain cap cases duplicated in `constellation_p06_composition_layout_test.dart`; keep one file of cap assertions. |
| 5 | `constellation_layout_positions_pinned_test.dart` | **merge** | Golden coordinate regression for `computeConstellationLayout`; nearly same lines as `constellation_layout_test.dart`—add as one group there. |
| 6 | `constellation_gather_test.dart` | **merge** | Pure gather geometry tests; subset of lines from `constellation_gather_batch_test.dart`—consolidate gather scenarios in batch file. |
| 7 | `domain/spatial_index_test.dart` | **merge** | Brute-force index unit tests; fully subsumed by `grid_index_equivalence_test.dart` which already compares implementations. |
| 8 | `radius_recipient_selection_test.dart` | **keep** | Small fast domain tests for radius math; subsumed in *coverage* by composer widget tests but not assertion-equivalent—keep for speed unless merged into domain suite. |
| 9 | `radius_recipient_selection_tag_test.dart` + `radius_recipient_selection_test.dart` | **keep** | Tag add/remove semantics (J≈0.96) are distinct from radius-only cases; keep both or merge into one `radius_recipient_selection_*` file without dropping tag cases. |
| 10 | `constellation_dense_cluster_web_tap_test.dart` | **merge** | J≈0.997 with touch-nearest; same #640 cluster but web semantics delivery—fold into `constellation_dense_cluster_touch_nearest_test.dart` as a group. |
| 11 | `constellation_touch_nearest_node_tap_test.dart` | **merge** | Third near-duplicate in dense-cluster tap cluster; merge pointer/mouse cases into touch-nearest master file. |
| 12 | `constellation_dense_cluster_touch_nearest_test.dart` | **keep** | Retain as the consolidated target for dense-cluster tap resolution (pointer + web + Chrome adjustment). |
| 13 | `constellation_tag_magnet_label_avoidance_test.dart` | **keep** | Subsumed in lines by magnet clearance but asserts label/chip placement avoidance on phone vs desktop—different expectations than obstacle clearance alone. |
| 14 | `constellation_tag_lens_panel_test.dart` | **keep** | Panel summary line and forward action; high overlap with tag hull rendering but asserts bottom-panel copy and counts, not hull geometry. |
| 15 | `constellation_preview_reveals_node_test.dart` | **keep** | Issue #458 camera pan when opening preview; body tests share fixture lines but do not assert pan-to-reveal beside/below sheets. |
| 16 | `constellation_realtime_refresh_test.dart` | **keep** | #234 fake-async fetch throttling; subsumed lines-wise by staleness window test but different timing/trigger story. |
| 17 | `constellation_peer_profile_edge_lookup_test.dart` | **keep** | Performance contract (O(1) edge lookup, counting list); line overlap with body is harness noise—assertions are not duplicated in body tests. |
| 18 | `constellation_edge_path_reuse_test.dart` | **keep** | Asserts dash path signatures stable across frames; dash build-count test shares lines but counts rebuilds, not visual correctness. |
| 19 | `constellation_remote_hint_delivery_pg_test.dart` vs `constellation_remote_hint_freshness_test.dart` | **keep** | J≈0.97; pg-named file mirrors server wire contract, freshness file focuses staleness—keep both until remote hint tests share one harness module. |
| 20 | `constellation_overlapping_dot_browser_touch_test.dart` | **fix then keep** | Failed this run (7 s, no lcov); likely environment/browser touch flake—repair before any delete; overlaps dense-cluster cluster once green. |

---

## Greedy set cover note

The greedy algorithm selected **126** of 225 files to cover all 18,915 line pairs. Removing the other 99 files would **not** reduce measured line coverage, but would almost certainly drop behavioural assertions. Treat this number as an upper bound on “files that are line-redundant with others,” not as a deletion list.

---

