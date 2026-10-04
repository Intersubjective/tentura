# Test-suite audit (2026-10)

**Why:** ~8 400 tests (client 4 690 · server 3 855 incl. ~1 700 Postgres-tagged · small packages ~160).
CI critical path is `test-client` (~20 min), then `test-pg` (~12 min), `test-server` (~5 min).

## TL;DR of what the data said

1. **Test count is not the cost driver; a handful of files and per-file load are.**
   Client, one full run: 1 309 s of test bodies + 1 409 s of suite loading (≈2 s × 670 files).
   Server non-pg: 79 s of bodies vs 320 s of loading.
2. **~25 % of client test time was one bug:** tear-downs did `await cubit.close().timeout(5 s)`; `close()` can't
   complete in the fake-async zone without a `pump()`, so *every* test in four Post/room files burned the full
   5 s timeout (≈100 tests × 5.3 s). Fixed (`pump()` then `await`) — the 97 tests now run in 19 s instead of ~340 s.
3. **One test ran `dart analyze` inside `flutter test`** (`constellation_cubit_analyzer_test`, 142 s = 11 % of client
   time). CI already runs the analyzer + custom lints; deleted.
4. **Line-coverage overlap is a weak redundancy signal here.** Of 165 client / 63 server files with *no unique
   lines*, almost all are tiny pure-logic unit tests (≈0.05 s each). Coverage proves a line was *executed*, not that
   a distinct behaviour was *asserted*; deleting them saves nothing and loses pinned behaviour. What coverage *did*
   find that is worth acting on: **identical-boot smoke tests** (3 server DI-smoke files each booting the whole
   graph → merged into one) and heavy widget files whose coverage is a subset of a sibling's (review queue below).
5. **Dead code with its own tests** (orphan lib files imported by nothing but their test) — see below.

## Method (reproducible, all under `scripts/test_audit/`)

| Step | Command | Output (`build/test_audit/`, git-ignored) |
|---|---|---|
| Static inventory, exact/near-duplicate bodies, stale imports | `python3 scripts/test_audit/inventory.py` | `tests.jsonl`, `dup_bodies.csv`, `stale_files.csv`, `report.md` |
| Per-test-file coverage + per-test timings | `scripts/run_with_test_cleanup.sh -- scripts/test_audit/collect.sh server\|client` then `python3 scripts/test_audit/ingest.py --pkg …` | `cov/<pkg>/*.json` |
| Overlap: unique lines, subset, twin (IDF-filtered), greedy minimal cover, slowest tests | `python3 scripts/test_audit/overlap.py --pkg …` | `overlap_<pkg>.{md,csv}` |
| Dead lib files + the tests that exist only for them | `python3 scripts/test_audit/orphans.py` | `orphans.csv` |
| Docs ↔ code drift (paths/identifiers cited in governing docs) | `python3 scripts/test_audit/doc_drift.py` | stdout |

Notes: server uses `dart test --coverage` (one `.vm.json` per file; needs `dart pub global activate coverage`).
Client needs a 12-line local patch to a throw-away Flutter SDK (`scripts/test_audit/flutter_sdk_patch.md`) because
stock `flutter test` merges all files into one lcov. A full server+client collection takes ≈10 + 21 min.
`pg`-tagged tests were **not** measured (no Postgres/MeritRank in the audit sandbox) — take timings from CI.
`-j` parallel runs produced 5 `sentry_*` failures on the server (and `di_smoke_test` dev/prod needs a live
Postgres); both reproduce without these changes.

## Done in this pass

- Fixed the 5 s tear-down timeouts (`post_view_screen`, `post_mute_pin_leave`, `post_convert_to_request_flow`,
  `room_capabilities_widget`).
- Deleted `constellation_cubit_analyzer_test.dart` (duplicates CI analyze).
- Merged `closure_ports_di_smoke`, `closure_reminder_sweeps_di_smoke` into `di_test_env_smoke_test.dart`
  (3 full-graph boots → 1, same assertions).
- Deleted `forward_candidate_context_di_test.dart` (regex over generated `di.config.dart`; brittle, the DI smoke
  tests prove the same composition).
- Docs: see "Docs" below.

## Review queue (needs an owner's eye — not done automatically)

**Dead code + its tests — done (second pass):** removed `coordination_target_candidates`, `admitted_chat_members`,
`ui/utils/normalize`, `mock/data/fixtures` (client) and `acknowledged_committer` (server) with their tests; rules/docs
that pointed at `mock/data/` updated. Kept on purpose: `server/lib/domain/beacon_access_policy.dart` (Dart mirror of the
SQL access matrix, checked by `beacon_access_level_parity_pg_test`). Other orphans without tests: `orphans.csv`.

**Widget-file merges — done (second pass)** with `scripts/test_audit/merge_tests.py` (unions imports/helpers, appends
`main()` bodies; aborts on name collisions): `beacon_surface_selection` → `beacon_back_navigation`;
`constellation_viewport_overlay` + `constellation_label_budget_widget` → `constellation_camera_controls`;
`constellation_node_tap_dispatch` → `constellation_body`. Test counts unchanged (7 / 12 / 22 → 41 total, all green).
Not merged: `nested_beacon_navigation` ↔ `request_thread_routing` (both mutate global `PageInfo` in `setUpAll`; merging
would change isolation). Expect only ~1–2 s saved per removed file (load cost), not a big win.

**Slow outliers:** `server/test/support/pg_required_mode_test.dart` (26 s without Postgres — probe retries),
`client/hook/wasm_preload_artifacts_test.dart` + `tool/verify_web_version_consistency_test.dart` (≈9 s each),
`inbox/activity_stream_view_test` "60 offers and 120 stream items" (10 s).

**Data-driven candidates** (`dup_bodies.csv`, 95 identical-shape groups): same body, different literals — fold into
loops/tables to cut LOC (no runtime gain). Mirror tests across client/server (`capability_slug_order`,
`coordination_response_type`, `constellation_anchor_domain`) are intentional wire-contract mirrors; keep.

**Policy for new tests:** no subprocess `dart analyze` / `flutter` inside tests; never mask a hanging tear-down with
`.timeout`; one DI boot per file; prefer extending an existing file over adding a one-test file (each file costs
≈1–2 s of load). `test-coverage-misses.md` is a closed historical backlog, not a todo list.
