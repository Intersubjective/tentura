# Audit: Dead and Unreachable Tests (Round T1)

**Date:** 2026-10-30
**Issue:** Refs #826
**Scope:** `packages/client/test`, `packages/server/test`, `test` (root package), `packages/client/test_driver`, `packages/client/integration_test`.

This audit documents dead, skipped, weak, duplicate, stale, unreachable, and orphaned tests in the repository. Per Issue #826, no code or test changes have been applied in this round.

---

## Category Summary Counts

| # | Category | Count | Primary Impact |
|---|---|---|---|
| 1 | **Skipped** | 11 | Tests explicitly skipped via `skip:` or `markTestSkipped` |
| 2 | **No assertions** | 8 | Tests with zero assertions or trivial expectations (`expect(true, isTrue)`) |
| 3 | **Stale behaviour** | 5 | Tests asserting removed screens (`UpdatesScreen`) or legacy wire protocols |
| 4 | **Dead targets** | 6 | Tests exercising classes/mocks in `lib/` that production code never references |
| 5 | **Duplicates** | 9 | Copy-pasted test suites or duplicate test names within the same file |
| 6 | **Unreachable in CI** | 21 | Test files excluded from CI (root `test/` tree, client `pg` tests, bench files) |
| 7 | **Orphan support** | 6 | Unused support files and fixtures under `test/support` and `test/fixtures` |
| **Total** | | **66** | |

---

## Category 1: Skipped Tests

| # | File:line | Test name | Why it's dead or weak | Recommendation |
|---|---|---|---|---|
| 1 | `packages/client/test/drift/tentura/migration_test.dart:53` | `migration from v1 to v2 does not corrupt data` | Hardcoded `skip: 'TODO: wire data-integrity fixtures after drift schema helper upgrade'`. | Rewrite test with schema verifier data fixtures or delete placeholder. |
| 2 | `packages/client/test/features/constellation/constellation_timeline_spans_test.dart:147` | `drop, layout, composition and scene work emit completed named spans` | Calls `markTestSkipped('VM Timeline capture needs flutter test --enable-vmservice');`. Standard CI runs plain `flutter test` without `--enable-vmservice`, so this test is always skipped in CI. | Move into a dedicated benchmark runner script or enable `--enable-vmservice` in a performance test job. |
| 3 | `packages/client/test/hook/wasm_preload_artifacts_test.dart:164` | `wasm preload artifacts generator` (Node check) | `markTestSkipped('node is not installed')` when Node runtime is unavailable. | Keep conditional skip; ensure Node is installed in CI environment. |
| 4 | `packages/client/test/web/sw_update_reload_test.dart:25` | `sw update reload` (Node check) | `markTestSkipped('node is not installed')` when Node runtime is missing. | Keep conditional skip. |
| 5 | `packages/server/test/api/controllers/graphql/mutation_beacon_people_test.dart:111` | `mutationsAll (evaluated) contains MarkBeaconPeopleSeen` | `markTestSkipped('Postgres not reachable; mutationsAll DI smoke needs TaskWorker')` when Postgres admin is unreachable. | Keep conditional skip or tag suite with `pg`. |
| 6 | `packages/server/test/api/hasura_beacon_expires_at_pg_test.dart:45` | `Docker unavailable` | `test('Docker unavailable', () {}, skip: 'Docker not available');` — dummy empty test block. | Delete dummy test block; disposable Postgres fixture already handles skips. |
| 7 | `packages/server/test/api/hasura_vote_beacon_post_guard_pg_test.dart:31` | `Docker unavailable` | `test('Docker unavailable', () {}, skip: 'Docker not available');` — dummy empty test block. | Delete dummy test block. |
| 8 | `packages/server/test/api/help_offer_post_hasura_pg_test.dart:48` | `Docker unavailable` | `test('Docker unavailable', () {}, skip: 'Docker not available');` — dummy empty test block. | Delete dummy test block. |
| 9 | `packages/server/test/api/post_hasura_read_pg_test.dart:53` | `Docker unavailable` | `test('Docker unavailable', () {}, skip: 'Docker not available');` — dummy empty test block. | Delete dummy test block. |
| 10 | `packages/server/test/api/post_inbox_hasura_pg_test.dart:54` | `Docker unavailable` | `test('Docker unavailable', () {}, skip: 'Docker not available');` — dummy empty test block. | Delete dummy test block. |
| 11 | `packages/server/test/api/post_room_block_hasura_pg_test.dart:59` | `Docker unavailable` | `test('Docker unavailable', () {}, skip: 'Docker not available');` — dummy empty test block. | Delete dummy test block. |

---

## Category 2: No Assertions / Weak Assertions

| # | File:line | Test name | Why it's dead or weak | Recommendation |
|---|---|---|---|---|
| 1 | `packages/client/test/widget_test.dart:8` | `placeholder` | `expect(true, isTrue);` — Trivial expectation that can never fail and tests no code. | Delete `widget_test.dart` or write real root widget smoke test. |
| 2 | `packages/client/test/drift/tentura/migration_test.dart:46` | `migration from v1 to v2 does not corrupt data` | Empty test body `() async {}` with no assertions. | Implement data integrity verification or remove. |
| 3 | `packages/server/test/api/hasura_beacon_expires_at_pg_test.dart:45` | `Docker unavailable` | Empty callback `() {}` with no expectations. | Delete dummy test. |
| 4 | `packages/server/test/api/hasura_vote_beacon_post_guard_pg_test.dart:31` | `Docker unavailable` | Empty callback `() {}` with no expectations. | Delete dummy test. |
| 5 | `packages/server/test/api/help_offer_post_hasura_pg_test.dart:48` | `Docker unavailable` | Empty callback `() {}` with no expectations. | Delete dummy test. |
| 6 | `packages/server/test/api/post_hasura_read_pg_test.dart:53` | `Docker unavailable` | Empty callback `() {}` with no expectations. | Delete dummy test. |
| 7 | `packages/server/test/api/post_inbox_hasura_pg_test.dart:54` | `Docker unavailable` | Empty callback `() {}` with no expectations. | Delete dummy test. |
| 8 | `packages/server/test/api/post_room_block_hasura_pg_test.dart:59` | `Docker unavailable` | Empty callback `() {}` with no expectations. | Delete dummy test. |

---

## Category 3: Stale Behaviour

| # | File:line | Test name | Why it's dead or weak | Recommendation |
|---|---|---|---|---|
| 1 | `packages/client/test/features/updates/notification_history_screen_test.dart:188` | `history screen shows receipts...` | Instantiates `home: const UpdatesScreen()`. `UpdatesScreen` was removed from client navigation and routes in June 2026 (`docs/client-ui-inventory.md`). | Remove or update test suite to target `NotificationCenterScreen`. |
| 2 | `packages/client/test/features/updates/notification_history_screen_test.dart:214` | `history search filters visible receipts` | Renders removed `UpdatesScreen()`. | Update test to target active notification UI. |
| 3 | `packages/client/test/features/updates/notification_history_screen_test.dart:240` | `history uses unscoped destination...` | Renders removed `UpdatesScreen()`. | Update test to target active notification UI. |
| 4 | `packages/client/lib/domain/entity/beacon_activity_event_consts.dart:56` | Legacy activity change reason `reviewWindowOpened` | Production constant `legacyClosureOpenReason = 'reviewWindowOpened'` is only asserted by tests after closure redesign. | Remove legacy pre-redesign wire fallback once DB migrations complete. |
| 5 | `packages/server/test/domain/use_case/beacon_room_case_plan_thread_test.dart:42` | `plan thread case` | Exercises legacy thread room creation logic before General-only room consolidation. | Rewrite to assert single General room semantics. |

---

## Category 4: Dead Targets

| # | File:line | Test name | Why it's dead or weak | Recommendation |
|---|---|---|---|---|
| 1 | `packages/client/lib/domain/entity/beacon_activity_event_consts.dart:2` | `BeaconActivityEventVisibilityBits` | Defined in `lib/` but has 0 production callers across `packages/client/lib`. Referenced only by 10 client test files. | Move constant into test helper or remove if unused in domain. |
| 2 | `packages/client/lib/data/gql/timestamptz_serializer.dart:7` | `TimestamptzSerializer` | Custom serializer defined in `lib/data/gql/` with 0 production call sites in `lib/`. Used only by GQL test utilities. | Remove or wire into Ferry GQL serializer plugin. |
| 3 | `packages/client/lib/data/repository/mock/client_repository_mocks.dart:7` | `ClosureRepositoryMock`, `BeaconLobbyRepositoryMock` | Mock classes defined inside production `lib/` tree (`packages/client/lib/data/repository/mock/`). Production code never references them. | Move mock classes from `lib/` to `test/support/`. |
| 4 | `packages/server/lib/data/repository/mock/pair_block_query_repository_mock.dart:6` | `PairBlockQueryRepositoryMock` | Mock class defined in server `lib/data/repository/mock/`. 0 callers in `packages/server/lib`. | Move mock repository out of production `lib/` into `test/support/`. |
| 5 | `packages/server/lib/data/repository/mock/trust_ledger_repository_mock.dart:5` | `TrustLedgerRepositoryMock` | Mock class defined in production `lib/`. 0 production references. | Move to `test/support/`. |
| 6 | `packages/server/lib/data/repository/mock/invite_seed_prompt_repository_mock.dart:5` | `InviteSeedPromptRepositoryMock` | Mock class defined in production `lib/`. 0 production references. | Move to `test/support/`. |

---

## Category 5: Duplicates

| # | File:line | Test name | Why it's dead or weak | Recommendation |
|---|---|---|---|---|
| 1 | `test/domain/availability_test.dart:92` | `limited+future pause is paused` | Identical availability entity test exists in `packages/client/test/domain/entity/availability_test.dart:49` and `packages/server/test/domain/entity/user_availability_entity_test.dart:58`. | Delete duplicate test file in root `test/domain/availability_test.dart`. |
| 2 | `test/domain/availability_test.dart:103` | `limited+past pause falls back to limited` | Identical test in client (`packages/client/test/domain/entity/availability_test.dart:58`) and server (`packages/server/test/domain/entity/user_availability_entity_test.dart:68`). | Delete root duplicate. |
| 3 | `packages/server/test/domain/attention/attention_intent_case_test.dart:498` | `excludes candidate when actor blocked them` | Duplicate test name and near-identical test body in same file at line 534 and line 604. | Consolidate or parameterize duplicate test cases. |
| 4 | `packages/server/test/domain/attention/attention_intent_case_test.dart:509` | `excludes candidate when they blocked actor` | Duplicate test name in same file at line 545 and line 618. | Consolidate duplicate test cases. |
| 5 | `packages/server/test/domain/use_case/beacon_case_media_test.dart:243` | `rejects an unauthorized caller before uploading` | Duplicate test name and logic in same file at line 358. | Remove duplicate test block. |
| 6 | `packages/server/test/domain/use_case/beacon_case_media_test.dart:255` | `rejects at the cap and compensates the upload` | Duplicate test name in same file at line 370. | Remove duplicate test block. |
| 7 | `packages/server/test/domain/use_case/beacon_fact_card_case_edit_test.dart:194` | `FactEditApplied returns the new seq` | Duplicate test name in same file at line 244. | Rename or consolidate test cases. |
| 8 | `packages/server/test/domain/use_case/beacon_fact_card_case_edit_test.dart:200` | `FactEditNoOp returns the current seq` | Duplicate test name in same file at line 251. | Rename or consolidate test cases. |
| 9 | `packages/server/test/domain/use_case/beacon_fact_card_case_edit_test.dart:205` | `FactEditNotFound → IdNotFoundException` | Duplicate test name in same file at line 256. | Rename or consolidate test cases. |

---

## Category 6: Unreachable in CI

| # | File:line | Test name | Why it's dead or weak | Recommendation |
|---|---|---|---|---|
| 1 | `test/mention_span_validation_test.dart:1` | Entire file | Located in root `test/` directory. CI pipeline (`pipeline.yml`) only runs `cd packages/server && dart test`, `cd packages/client && flutter test`, and `cd packages/tentura_lints && dart test`. Root `test/` is never selected. | Move root tests into `packages/client/test` or `packages/server/test`, or add root test job to CI. |
| 2 | `test/domain/availability_test.dart:1` | Entire file | Located in root `test/` directory; ignored by CI pipeline. | Delete (duplicate of client/server availability tests) or move. |
| 3 | `test/domain/next_step_mention_test.dart:1` | Entire file | Located in root `test/` directory; ignored by CI. | Move to `packages/client/test/domain/`. |
| 4 | `test/domain/entity/beacon_post_lifetime_test.dart:1` | Entire file | Located in root `test/` directory; ignored by CI. | Move to `packages/server/test/domain/entity/`. |
| 5 | `test/domain/entity/beacon_hierarchy_entities_test.dart:1` | Entire file | Located in root `test/` directory; ignored by CI. | Move to `packages/client/test/domain/entity/`. |
| 6 | `test/domain/entity/beacon_status_discussion_writes_test.dart:1` | Entire file | Located in root `test/` directory; ignored by CI. | Move to `packages/server/test/domain/entity/`. |
| 7 | `test/domain/entity/beacon_access_test.dart:1` | Entire file | Located in root `test/` directory; ignored by CI. | Move to `packages/server/test/domain/entity/`. |
| 8 | `test/domain/entity/coordinates_test.dart:1` | Entire file | Located in root `test/` directory; ignored by CI. | Move to `packages/client/test/domain/entity/`. |
| 9 | `test/domain/entity/person_auto_tag_kind_test.dart:1` | Entire file | Located in root `test/` directory; ignored by CI. | Move to `packages/client/test/domain/entity/`. |
| 10 | `test/domain/entity/beacon_status_transition_test.dart:1` | Entire file | Located in root `test/` directory; ignored by CI. | Move to `packages/server/test/domain/entity/`. |
| 11 | `test/domain/entity/beacon_status_allows_edit_test.dart:1` | Entire file | Located in root `test/` directory; ignored by CI. | Move to `packages/server/test/domain/entity/`. |
| 12 | `packages/client/test/domain/attention/attention_read_clear_axis_test.dart:1` | `@Tags(['pg'])` client test | Tagged `pg`. `pipeline.yml` runs `flutter test ... --exclude-tags pg` for client shards because client runners lack Postgres. This test only runs locally. | Refactor to mock DB or add Postgres service container to client CI runner. |
| 13 | `packages/client/test/architecture/updates_event_contract_test.dart:1` | `@Tags(['pg'])` client test | Tagged `pg`; excluded in CI client shards. | Refactor to use unit mocks or include in server DB contract suite. |
| 14 | `packages/client/test/features/profile_view/profile_untrust_mutation_contract_test.dart:1` | `@Tags(['pg'])` client test | Tagged `pg`; excluded in CI client shards. | Refactor or run in local-only integration suite. |
| 15 | `packages/client/test/features/people_tags/populated_tag_delete_screen_pg_test.dart:1` | `@Tags(['pg'])` client test | Tagged `pg`; excluded in CI client shards. | Refactor or run in local-only integration suite. |
| 16 | `packages/client/test/features/inbox/inbox_provenance_latest_note_test.dart:1` | `@Tags(['pg'])` client test | Tagged `pg`; excluded in CI client shards. | Refactor or run in local-only integration suite. |
| 17 | `packages/client/test/bench/spatial_index_bench.dart:1` | Non-`_test.dart` benchmark | File named `spatial_index_bench.dart`. Test selection script `ci_select_tests.py` filters for `*_test.dart` only; this file is ignored by CI. | Rename to `spatial_index_bench_test.dart` or add to bench runner. |
| 18 | `packages/client/test/bench/uniform_grid_index.dart:1` | Non-`_test.dart` file | Ignored by CI selection scripts (`ci_select_tests.py`). | Rename or include in spatial bench test entrypoint. |
| 19 | `packages/client/test/bench/dynamic_aabb_tree_index.dart:1` | Non-`_test.dart` file | Ignored by CI selection scripts (`ci_select_tests.py`). | Rename or include in spatial bench test entrypoint. |
| 20 | `packages/client/test/bench/spatial_bench_geometry.dart:1` | Non-`_test.dart` file | Ignored by CI selection scripts (`ci_select_tests.py`). | Rename or include in spatial bench test entrypoint. |
| 21 | `packages/client/test/bench/sweep_and_prune_index.dart:1` | Non-`_test.dart` file | Ignored by CI selection scripts (`ci_select_tests.py`). | Rename or include in spatial bench test entrypoint. |

---

## Category 7: Orphan Support

| # | File:line | Test name / File | Why it's dead or weak | Recommendation |
|---|---|---|---|---|
| 1 | `packages/server/test/support/lane_hold_perf_workloads.dart:1` | `lane_hold_perf_workloads.dart` | Support file under `packages/server/test/support/` with 0 import references across all test files in the repository. | Delete orphan support file or wire into perf benchmark harness. |
| 2 | `packages/client/test/fixtures/tentura_q8s8_beacon_operational_header_pre_mount.dart:1` | `tentura_q8s8_beacon_operational_header_pre_mount.dart` | Fixture file under `packages/client/test/fixtures/` with 0 import references across tests. | Delete orphan fixture. |
| 3 | `packages/client/test/features/constellation/fixtures/legacy_layout/5b8493621d3934eca8059b23197a01029123d952/constellation_layout.dart.txt:1` | `constellation_layout.dart.txt` | Text layout fixture with 0 references in client test files. | Delete stale legacy layout fixture. |
| 4 | `packages/client/test/features/constellation/fixtures/legacy_layout/5b8493621d3934eca8059b23197a01029123d952/radial_hop_positions.dart.txt:1` | `radial_hop_positions.dart.txt` | Text position fixture with 0 references in client test files. | Delete stale legacy layout fixture. |
| 5 | `test/fixtures/agents_alloy_memory_5zq_lesson_snippet.txt:1` | `agents_alloy_memory_5zq_lesson_snippet.txt` | Root fixture file unreferenced by any test. | Delete orphan text fixture. |
| 6 | `test/fixtures/agents_alloy_memory_tail_unified_after_5zq.txt:1` | `agents_alloy_memory_tail_unified_after_5zq.txt` | Root fixture file unreferenced by any test. | Delete orphan text fixture. |

---

## Top 15 to act on first

Based on CI impact, dead code clutter, and risk of false confidence, here are the top 15 items to remediate first:

1. **Root `test/` directory test files (`test/mention_span_validation_test.dart:1`, `test/domain/...`)** — 11 test files in the repository root are completely bypassed by CI pipeline jobs (`pipeline.yml`). Move them to `packages/client/test` or `packages/server/test`.
2. **`packages/client/test/widget_test.dart:8` (`placeholder`)** — Trivial `expect(true, isTrue)` placeholder test providing zero test coverage. Replace with real UI smoke test or remove.
3. **`packages/client/test/features/updates/notification_history_screen_test.dart:188`** — Asserts removed `UpdatesScreen` widget; replace target with active notification screen.
4. **`packages/client/test/domain/attention/attention_read_clear_axis_test.dart:1` (and 4 other client `pg` tests)** — Client tests tagged `pg` are silently excluded in CI (`--exclude-tags pg`). Refactor to unit mocks or provide Postgres in client CI runner.
5. **`packages/client/test/drift/tentura/migration_test.dart:53`** — Hardcoded `skip` on schema data integrity migration test. Wire real schema verifier fixtures.
6. **`packages/client/lib/data/repository/mock/client_repository_mocks.dart:7`** — Production `lib/` mock repository implementations. Move out of `lib/` to `test/support/`.
7. **`packages/server/lib/data/repository/mock/pair_block_query_repository_mock.dart:6`** — Production server `lib/` mock repository implementations. Move out of `lib/` to `test/support/`.
8. **`packages/server/test/api/hasura_beacon_expires_at_pg_test.dart:45` (and 5 matching files)** — Empty `Docker unavailable` test functions with no assertions; remove dummy test blocks.
9. **`packages/server/test/domain/attention/attention_intent_case_test.dart:498`** — Duplicate test blocks with identical names in the same test file (lines 498, 534, 604). Consolidate test cases.
10. **`packages/server/test/domain/use_case/beacon_case_media_test.dart:243`** — Duplicate test blocks in the same file (lines 243 & 358). Remove duplicate block.
11. **`packages/client/test/bench/spatial_index_bench.dart:1` (and benchmark support files)** — Benchmark files missing `_test.dart` suffix, causing `ci_select_tests.py` to skip them. Rename to `*_test.dart` or add explicit bench runner script.
12. **`packages/client/lib/domain/entity/beacon_activity_event_consts.dart:2` (`BeaconActivityEventVisibilityBits`)** — Dead `lib/` entity with 0 production references. Remove or relocate to test support.
13. **`packages/server/test/support/lane_hold_perf_workloads.dart:1`** — Orphan support file with 0 imports. Delete.
14. **`packages/client/test/fixtures/tentura_q8s8_beacon_operational_header_pre_mount.dart:1`** — Orphan fixture file with 0 imports. Delete.
15. **`test/domain/availability_test.dart:92`** — Duplicate availability entity test suite matching client/server unit test files. Delete root duplicate.
