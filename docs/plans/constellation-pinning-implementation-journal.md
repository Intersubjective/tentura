# Constellation pinning implementation journal

## Scope

- Objective: implement `docs/plans/constellation-pinning-plan.md` packets P01–P12.
- Repository: `/home/vader/MY_SRC/tentura`
- Branch: `feature/pin_constellation`
- Starting commit: `b61c44880e047bac66caafe045bae7eb9552dbb9`
- Started: 2026-09-11

## Worktree boundary at start

The following pre-existing untracked paths are outside this implementation and
must not be modified, staged, or committed:

```text
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
docs/plans/issue-130-first-run-orientation-plan.md
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
tg_style_research.md
```

## Ordered manifest

| Packet | Status | Dependency | Evidence / commit |
|---|---|---|---|
| P01 Contract fixtures and domain types | complete | — | see checkpoint below |
| P02 Migration and storage adapter | complete (concurrency-proof remediated) | P01 | see checkpoint below |
| P03 Server membership and complete snapshot | complete (remediated) | P02 | see checkpoint below |
| P04 Authenticated V2 API | complete (accepted) | P03 | see checkpoint below |
| P05 Client wire adapters and server echo policy | in progress (P05b client wire) | P04 | P05a see checkpoint |
| P06 Pure composition, budgets and layout | pending | P05 | — |
| P07 Graph gesture adapter | pending | P06 | — |
| P08 Placement orchestration and live reconciliation | pending | P07 | — |
| P09 Map/Text controls, filters and status accessibility | pending | P08 | — |
| P10 End-to-end and failure acceptance | pending | P09 | — |
| P11 Full verification and release preparation | pending | P10 | — |
| P12 Product docs and coordinated activation | pending | P11 | — |

## Required process and verification discipline

- One fresh non-fast Composer 2.5 worker at a time.
- Heavy integration, browser, PostgreSQL, code generation, and full-suite work
  runs serially. Never start more than one such command at once.
- After every worker exit, the overseer records a process audit for task-owned
  or dangling Chrome, Dart, analyzer, Flutter, test-driver, and server
  processes before launching the next worker.
- Generated sources are regenerated only through their generators and are not
  hand-edited or committed.
- Every coherent implementation step is independently checked and committed
  with only its owned paths.

## Acceptance matrix

P01–P10 use their packet-specific checks from the plan. P11 requires serial
codegen, focused and full server/client/graph/lint/terminology checks, a unique
disposable PostgreSQL database for tagged PG tests, serial browser runners, and
versioned web artifact verification under one `WEB_BUILD_ID`. P12 records the
operational and product documentation only after those gates are accounted for.

## Checkpoints

### Initialization — 2026-09-11

- Status: accepted coordination setup.
- Verified: repository root, branch, starting SHA, pre-existing worktree list,
  and Cursor `composer-2.5` availability.
- Process baseline: long-running user/editor Chrome, Cursor, and Dart language
  servers exist; no task-owned worker has started. These must not be killed as
  cleanup.
- Decision: create the required journal before P01 so every fresh worker has
  shared state. Its initial setup is committed separately by the overseer.

### P01 — Contract fixtures and domain types — 2026-09-11

- Added client/server domain types: `ConstellationAnchorTarget` (sealed
  person/beacon), `ConstellationAnchorPosition` validation, `BigInt` revision
  parsing, `ConstellationAnchor`, projection mode, membership filters, anchor
  projection shell, C2 beacon status sets, v1 geometry constants.
- Extended `ConstellationField` / `ConstellationFieldSnapshot` with optional
  anchor projection; client `ConstellationRepositoryPort.fetch` accepts filter
  and projection parameters (ignored by repository until P05); server port
  documents `ConstellationFieldReadParams` for P03.
- Tests and serializable fixture maps for C1/C2 boundaries (coordinates,
  revisions > 2^53, ego person, shared raw id / distinct typed keys, status
  filters).
- Commands:
  - `cd packages/client && dart run build_runner build -d --build-filter="lib/features/constellation/domain/entity/*"` → exit 0 (8 outputs)
  - `cd packages/client && flutter test test/features/constellation/constellation_anchor_domain_test.dart` → 31 passed
  - `cd packages/server && dart test test/domain/entity/constellation_anchor_domain_test.dart` → 30 passed
  - `cd packages/server && dart test test/domain/use_case/constellation_field_case_test.dart` → 13 passed
  - `dart analyze` on P01-owned paths → no errors (info-level lints only)
- Note: full `build_runner` for client was run once to refresh freezed for
  `constellation_field`; `constellation_field.freezed.dart` is gitignored locally.
- Note: repo-wide `check-custom-lints.sh packages/client` still reports
  pre-existing unrelated analyzer errors (e.g. missing L10n getters); P01
  constellation stub overrides were updated.

STATUS: complete

COMMITS:
- bab241abc feat(constellation): add P01 anchor domain types and contract fixtures

TESTS:
- `cd packages/client && flutter test test/features/constellation/constellation_anchor_domain_test.dart` → 31 passed
- `cd packages/server && dart test test/domain/entity/constellation_anchor_domain_test.dart` → 30 passed
- `cd packages/server && dart test test/domain/use_case/constellation_field_case_test.dart` → 13 passed
- `dart analyze` on P01-owned client/server paths → exit 0 (info only)

FILES:
- packages/client/lib/features/constellation/domain/entity/constellation_anchor.dart
- packages/client/lib/features/constellation/domain/entity/constellation_anchor_projection.dart
- packages/client/lib/features/constellation/domain/entity/constellation_field.dart
- packages/client/lib/features/constellation/domain/constellation_consts.dart
- packages/client/lib/features/constellation/domain/port/constellation_repository_port.dart
- packages/client/lib/features/constellation/data/repository/constellation_repository.dart
- packages/client/test/features/constellation/constellation_anchor_*.dart
- packages/client/test/features/constellation/constellation_*_test.dart (stub fetch signature)
- packages/server/lib/domain/entity/constellation_anchor.dart
- packages/server/lib/domain/entity/constellation_anchor_projection.dart
- packages/server/lib/domain/entity/constellation_field.dart
- packages/server/lib/domain/port/constellation_field_repository_port.dart
- packages/server/lib/consts/constellation_consts.dart
- packages/server/test/domain/entity/constellation_anchor_*.dart
- docs/plans/constellation-pinning-implementation-journal.md

FINDINGS:
- `BigInt` / `static final` empty projection required because const defaults
  cannot reference `BigInt.zero` or non-const `empty` singletons in Freezed.
- Client `ConstellationField.anchorProjection` is nullable; use
  `resolvedAnchorProjection` for empty-default semantics until P05 fills wire data.
- `ConstellationFieldSnapshot` lost `const` constructor on server due to
  non-const default anchor projection.
- Revision `9007199254740992` (2^53) is valid and still JS-safe-integer; first
  value strictly above 2^53 is `9007199254740993`.

REMAINING: none for P01 (P02 migration/storage is next per plan).

### P02 — Migration and storage adapter — 2026-09-11

- `m0167`: `constellation_anchor` / `constellation_anchor_cursor` tables with
  CHECK/FK/partial-unique indexes; `bump_constellation_anchor_revision` BEFORE
  trigger; `notify_constellation_anchor_change` AFTER strict publisher;
  `person_are_mutually_visible_cached` read-only cache-miss branch (C4).
- Drift table sources registered on `TenturaDb`; `withReadSnapshot` helper and
  `ReadSnapshotPort` / `ReadSnapshotUnitOfWork`.
- `ConstellationAnchorRepositoryPort` + `ConstellationAnchorRepository`:
  cursor-first `FOR UPDATE`, upsert/update-insert, idempotent absent delete with
  single cursor bump + explicit `delete` publication, one top-level retry for
  `40P01`/`40001`.
- Deferred to P03/P04/P08: C2 upsert authorization, field membership, GraphQL,
  realtime manifest/contract subscriber wiring.
- Commands (serial):
  - `cd packages/server && dart run build_runner build -d` → exit 0
  - `cd packages/server && dart test test/data/database/constellation_anchor_storage_pg_test.dart -j 1` → 15 passed
  - `cd packages/server && dart test test/data/repository/constellation_anchor_repository_pg_test.dart -j 1` → 3 passed
  - `./scripts/check-custom-lints.sh packages/server` → OK (custom-lint total 0)
- PostgreSQL: disposable DB names
  `tentura_test_ca_*` / `tentura_test_carepo_*`; `SELECT current_database()`
  asserted in storage setup; fresh migrate + upgrade from `0166` through `0167`.

STATUS: complete

COMMITS:
- 138e998b3 feat(server): add constellation anchor storage migration m0167
- a3e829d1e feat(server): add constellation anchor repository and PG tests

TESTS:
- `cd packages/server && dart test test/data/database/constellation_anchor_storage_pg_test.dart -j 1` → 15 passed
- `cd packages/server && dart test test/data/repository/constellation_anchor_repository_pg_test.dart -j 1` → 3 passed
- `./scripts/check-custom-lints.sh packages/server` → exit 0

FILES:
- packages/server/lib/data/database/migration/m0167.dart
- packages/server/lib/data/database/migration/_migrations.dart
- packages/server/lib/data/database/table/constellation_anchors.dart
- packages/server/lib/data/database/table/constellation_anchor_cursors.dart
- packages/server/lib/data/database/tentura_db.dart
- packages/server/lib/domain/port/constellation_anchor_repository_port.dart
- packages/server/lib/domain/port/read_snapshot_port.dart
- packages/server/lib/data/repository/constellation_anchor_repository.dart
- packages/server/lib/data/repository/read_snapshot_unit_of_work.dart
- packages/server/test/data/database/constellation_anchor_storage_pg_test.dart
- packages/server/test/data/repository/constellation_anchor_repository_pg_test.dart
- docs/plans/constellation-pinning-implementation-journal.md

FINDINGS:
- Drift `customSelect` returns `placed_at` as a string; repository parses with
  `DateTime.parse`.
- Concurrent same-viewer mutations serialize on `constellation_anchor_cursor`
  `FOR UPDATE`; beacon FK cascade vs cursor-first upsert needed repository
  deadlock retry in at least one direction.
- Realtime manifest / `realtime_entity_contract_test` publisher list updates
  remain P08 per plan (trigger function lives in `m0167`).

REMAINING: none for P02 (P03 field membership snapshot is next).

### P02 remediation — 2026-09-11

- Addressed reject gaps: explicit one-retry success + exhaustion (no third
  attempt), both deadlock victim directions (orchestrated upsert vs cascade),
  beacon + person target cascades, viewer/cursor deletion orders (account
  cascade + cursor-missing anchor delete), person+beacon notification coverage.
- Implementation: `withPostgresDeadlockOrSerializationRetry` in data layer;
  repository uses it with optional `transactionRetry` injection for PG proofs
  only. `ReadSnapshotPort` / `ReadSnapshotUnitOfWork` kept as thin C4 wrapper
  over `TenturaDb.withReadSnapshot` (no conflict with future
  `ConstellationFieldRepositoryPort.readSnapshot`).
- Note: multi-anchor `DELETE FROM "user"` in one statement hit a live FK/cascade
  interaction in local PG; acceptance uses per-row anchor deletes for dual-target
  notification proof plus single-anchor viewer account delete.
- Commands (serial):
  - `cd packages/server && dart test test/data/database/postgres_serialization_retry_test.dart -j 1` → 5 passed
  - `cd packages/server && dart test test/data/repository/constellation_anchor_repository_pg_test.dart -j 1` → 7 passed
  - `cd packages/server && dart test test/data/database/constellation_anchor_storage_pg_test.dart -j 1` → 18 passed
  - `./scripts/check-custom-lints.sh packages/server` → exit 0

STATUS: complete

COMMITS:
- 165b3e6fc fix(server): centralize constellation anchor deadlock retry (C3)
- 3c9f565e1 test(server): strengthen P02 constellation anchor PG and retry coverage

TESTS: see Commands above (all exit 0)

FILES:
- packages/server/lib/data/database/postgres_serialization_retry.dart
- packages/server/lib/data/repository/constellation_anchor_repository.dart
- packages/server/test/data/database/postgres_serialization_retry_test.dart
- packages/server/test/data/database/constellation_anchor_storage_pg_test.dart
- packages/server/test/data/repository/constellation_anchor_repository_pg_test.dart

FINDINGS:
- Retry loop is now explicit `maxRetries = 1` (two attempts total); exhaustion
  rethrows without calling the mutation closure again.
- `transactionRetry` constructor hook is test-only wiring; Injectable default
  path unchanged.
- Bulk `DELETE` of multiple anchor rows produced fewer LISTEN events than
  two single-row deletes in the PG harness (sequential deletes used).

REMAINING: none for P02 remediation (P03 next).

### P03 — Server membership and complete snapshot — 2026-09-11

- `ConstellationFieldRepositoryPort.readSnapshot` + `ConstellationFieldCase.readSnapshot`;
  `load()` delegates to FULL/default filters.
- `ConstellationFieldSnapshotReader` inside top-level `TenturaDb.withReadSnapshot`:
  watermark, authorized dormant anchors, pinned layer, batch C2 participation SQL,
  server filter IDs/count, support closure via shared
  `constellation_path_resolution.dart` / `constellation_field_selection.dart`.
- FULL composes automatic peers/requests excluding pinned/support budget charges;
  ANCHORS returns empty automatic arrays without discovery SQL.
- PG probe hook `constellation_field_snapshot_probe.dart` asserts repeatable-read/on
  during snapshot reads including profile batch lookup in the same Drift zone.
- Commands (serial):
  - `cd packages/server && dart test test/domain/use_case/constellation_field_case_test.dart test/domain/constellation/constellation_path_resolution_test.dart -j 1` → 17 passed
  - `cd packages/server && dart test test/data/repository/constellation_field_repository_pg_test.dart -j 1` → 16 passed
  - `./scripts/check-custom-lints.sh packages/server` → exit 0

STATUS: complete

COMMITS:
- 5ffaac2c8 feat(server): implement P03 constellation field read snapshot

TESTS: see Commands above (all exit 0)

FILES:
- packages/server/lib/data/repository/constellation_field_repository.dart
- packages/server/lib/data/repository/constellation_field_snapshot_reader.dart
- packages/server/lib/data/repository/constellation_field_snapshot_probe.dart
- packages/server/lib/domain/constellation/constellation_field_selection.dart
- packages/server/lib/domain/constellation/constellation_path_resolution.dart
- packages/server/lib/domain/port/constellation_field_repository_port.dart
- packages/server/lib/domain/use_case/constellation_field_case.dart
- packages/server/lib/domain/entity/constellation_field.dart
- packages/server/test/data/repository/constellation_field_repository_pg_test.dart
- packages/server/test/domain/use_case/constellation_field_case_test.dart
- packages/server/test/domain/constellation/constellation_path_resolution_test.dart

FINDINGS:
- `beacon_can_read_content` still requires discoverability (or offer/participant/forward)
  for peer Beacons; pinned/readable non-discoverable fixtures need an explicit read path
  (help offer used in PG tests).
- Non-discoverable automatic layer unchanged; pinned layer bypasses discoverability via
  anchor authorization + read wall on pinned Beacon ids only.
- `ConstellationRequestRecord.viewerParticipates` carries batch participation SQL results
  for pinned Beacon classification; wire mapping unchanged until P04.

REMAINING: P04 GraphQL/API (`constellationField` args, anchor mutations, exception codes).

### P03 remediation — manager review — 2026-09-11

- **Finding 1 (ring/residual):** `_buildAnchorProjection` now unions
  `resolution.ring` into support peers (excluding pinned people), expands path
  `visiblePeerIds` with `pathHolderIds` for pinned closure, and loads author
  profiles for pinned Requests. No fabricated trust edges for ring holders.
- **Finding 2 (C2 coverage):** Added
  `constellation_field_selection_test.dart` (lifecycle statuses 0/7/8/5/4/6,
  dormant cancelled/unknown, `participatedOnly`) and disposable-DB
  `constellation_viewer_participates_sql_test.dart` (author, commitment,
  admission, participant, active offer, decline-only, forward-only exclusion).
- **Finding 3 (`serverFilteredBeaconIds`):** PG proofs for sorted deduped
  lifecycle filter-hidden IDs, cancelled dormant pins omitted from filter list,
  `participatedOnly` filter-hidden vs visible transitions.
- **Finding 4 (FULL/ANCHORS):** Orphan-author residual test runs both
  projections; ANCHORS automatic arrays stay empty.
- **Finding 5 (C4 cache):** PG readonly snapshot still skips cache writes;
  added RW `person_are_mutually_visible_cached` population proof.
- **Probe:** Removed global `constellationFieldSnapshotOpenProbe`; PG isolation
  proof uses `@visibleForTesting snapshotOpenProbe` on
  `ConstellationFieldRepository` only.
- Commands (serial):
  - `cd packages/server && dart test test/domain/use_case/constellation_field_case_test.dart -j 1` → 15 passed
  - `cd packages/server && dart test test/data/repository/constellation_field_repository_pg_test.dart -j 1` → 22 passed
  - `cd packages/server && dart test test/domain/constellation/constellation_field_selection_test.dart test/domain/constellation/constellation_viewer_participates_sql_test.dart test/domain/constellation/constellation_path_resolution_test.dart -j 1` → 17 passed
  - `./scripts/check-custom-lints.sh packages/server` → exit 0

STATUS: complete (remediated; prior 5ffaac2c8 / eea5dccaf superseded by 8867e7759)

COMMITS:
- 8867e7759 fix(server): remediate P03 anchor closure and C2 test coverage

TESTS: see Commands above (all exit 0)

FILES:
- packages/server/lib/data/repository/constellation_field_repository.dart
- packages/server/lib/data/repository/constellation_field_snapshot_reader.dart
- packages/server/test/data/repository/constellation_field_repository_pg_test.dart
- packages/server/test/domain/constellation/constellation_field_selection_test.dart
- packages/server/test/domain/constellation/constellation_viewer_participates_sql_test.dart
- packages/server/test/domain/constellation/constellation_path_resolution_test.dart

FINDINGS:
- Prior commits omitted ring holders from anchor support peers and did not union
  holders into path visibility for closure edge filtering.
- Participation SQL still treats any historical admission `action IN (0,1)` as
  participation even after a later decline-only row; decline exclusion is
  exercised only when no prior admit/accept row exists (matches live SQL).
- Live PG `constellation_trust_edges` in the field-repository harness needs the
  full merit/trust seed used in `constellation_trust_edges_pg_test.dart`; path
  closure with support edges is covered in pure resolver tests instead.

REMAINING: P04 GraphQL/API.

### P04 — Authenticated V2 API — 2026-09-11

- `constellationField(showClosed, participatedOnly, projection)` with server-owned
  `kConstellationContext`; `anchorProjection` on wire; `FULL` / `ANCHORS` enum.
- `constellationAnchorUpsert` / `constellationAnchorDelete` mutations;
  `ConstellationAnchorCase`; codes `1700`–`1703` via `ConstellationException`.
- Upsert authorization after cursor `FOR UPDATE` via shared C2 SQL helper
  (`constellation_anchor_upsert_authorization.dart`); PG harness trust seeds.
- Commands (serial):
  - `cd packages/server && dart test test/api/controllers/graphql/constellation_anchor_test.dart -j 1` → 15 passed
  - `cd packages/server && dart test test/domain/use_case/constellation_field_case_test.dart -j 1` → 15 passed
  - `./scripts/check-custom-lints.sh packages/server` → exit 0

STATUS: complete

COMMITS:
- 2080c78ed feat(server): add P04 constellation anchor V2 GraphQL API

TESTS: see Commands above (all exit 0)

FILES:
- packages/server/lib/domain/use_case/constellation_anchor_case.dart
- packages/server/lib/api/controllers/graphql/mutation/mutation_constellation_anchor.dart
- packages/server/lib/api/controllers/graphql/query/query_constellation_field.dart
- packages/server/lib/api/controllers/graphql/mappers/constellation_gql_maps.dart
- packages/server/lib/api/controllers/graphql/custom_types.dart
- packages/server/lib/domain/exception.dart
- packages/server/lib/domain/exception_codes.dart
- packages/server/lib/data/repository/constellation_anchor_repository.dart
- packages/server/lib/data/repository/constellation_anchor_upsert_authorization.dart
- packages/server/test/api/controllers/graphql/constellation_anchor_test.dart

FINDINGS:
- Isolated GraphQL test schema must not import full `queriesAll`/`mutationsAll`
  (GetIt defaults); constellation-only `GraphQL` + `customTypes` suffices.
- `di.config.dart` is gitignored; `ConstellationAnchorCase` registers via local
  `build_runner` on deploy/CI codegen paths.

REMAINING: P05 client wire adapters and server echo policy.

### P02 concurrency-proof remediation — 2026-09-11

- Manager rejection (prior attempt): (A) upsert “deadlock victim” used 20 ms sleep
  and final coordinates only—no proof retry ran or `40P01` occurred; (B) cascade
  “deadlock victim” blocked cursor during delete/upsert without asserting
  deadlock, rollback, or victim side; (C) retry exhaustion injected
  `transactionRetry` before `withMutatingUser`, so no proof of post-mutation
  rollback or unchanged cursor/row/NOTIFY; (D) helper unit test title claimed
  “rolls back” without a transaction.
- Fix: removed injectable `transactionRetry` seam from
  `ConstellationAnchorRepository`; production keeps C3 semantics (`maxRetries =
  1`, `40P01`/`40001` only, whole `withMutatingUser` action retried). PG proofs
  use disposable DB + `p02_retry_probe` temp triggers raising SQLSTATE `40P01`
  after anchor row mutation (`mutation_seq` asserts exactly two attempts).
  Upsert fail-first + always-raise exhaustion assert `ServerException` `40P01`,
  unchanged coordinates/revision/watermark, and zero `entity_changes` NOTIFY on
  exhaustion; delete fail-first covers the inverse mutation path. Concurrent
  beacon/person cascade tests remain integration coverage without labeling mere
  waits as deadlocks (PostgreSQL does not deterministically pick cascade vs
  cursor-first victim). Renamed helper unit test to describe retry invocation,
  not rollback.
- Commands (serial):
  - `cd packages/server && dart test test/data/database/postgres_serialization_retry_test.dart -j 1` → 5 passed
  - `cd packages/server && dart test test/data/repository/constellation_anchor_repository_pg_test.dart -j 1` → 7 passed
  - `cd packages/server && dart test test/data/database/constellation_anchor_storage_pg_test.dart -j 1` → 18 passed
  - `./scripts/check-custom-lints.sh packages/server` → exit 0

STATUS: complete

COMMITS: (this journal commit follows code commit)

TESTS: see Commands above (all exit 0)

FILES:
- packages/server/lib/data/repository/constellation_anchor_repository.dart
- packages/server/test/data/database/constellation_anchor_pg_retry_probe.dart
- packages/server/test/data/database/postgres_serialization_retry_test.dart
- packages/server/test/data/repository/constellation_anchor_repository_pg_test.dart
- docs/plans/constellation-pinning-implementation-journal.md

FINDINGS:
- Synthetic `40P01` via `RAISE EXCEPTION USING ERRCODE = '40P01'` after
  `bump_constellation_anchor_revision` work in the same transaction proves
  rollback of cursor/row/notification before the repository’s single retry.
- Lock-order victim selection for real FK cascades is not deterministic; honest
  acceptance uses SQLSTATE probes on UPDATE and DELETE mutation paths plus
  existing concurrent cascade completion tests.

REMAINING: none for P02 (P03 next).

### P01 manager review — 2026-09-11

- Verdict: accepted. `bab241abc` contains only P01 contract types, contract
  fixtures, affected fake repository signatures, and the P01 journal record;
  `145b9a982` records the final worker status. No generated source was staged.
- Independently passed, one command at a time:
  - `cd packages/client && flutter test test/features/constellation/constellation_anchor_domain_test.dart` — 31 passed.
  - `cd packages/server && dart test test/domain/entity/constellation_anchor_domain_test.dart && dart test test/domain/use_case/constellation_field_case_test.dart` — 30 and 13 passed.
  - `./scripts/check-custom-lints.sh packages/server` — custom-lint total 0, baseline 0.
- Client custom-lint accounting is unchanged at 32, matching its baseline.
  `./scripts/check-custom-lints.sh packages/client` exits 3 before the custom
  count because generated client l10n is stale: five existing missing L10n
  members in Inbox/Home/Updates widgets. These paths are outside P01 and are
  neither caused nor fixed here; the final P11 gate remains blocked until the
  client localization generation/state is repaired and rechecked.
- Scope note: the client fetch and server field port only introduce typed
  future read parameters; the client repository intentionally does not send
  them until P05 and the server has no P03 snapshot implementation yet. This
  is an explicit P01 seam, not a claim of live filter/projection behavior.
- Process audit after worker: no task-owned Cursor, Dart test/analyzer,
  Flutter, Chrome, WebDriver, or test-driver process remained. Pre-existing
  editor/browser services and an unrelated zombie audio helper were left
 untouched.

### P02 manager review — 2026-09-11

- Verdict: accepted. Reviewed `138e998b3`, `a3e829d1e`, `165b3e6fc`, `3c9f565e1`, and `7afc91d5f`; no generated source or pre-existing user work was staged. `7afc91d5f` removes the test-injection seam and exercises the repository's actual top-level retry through disposable PostgreSQL `40P01` triggers that fire after the anchor mutation begins. The nontransactional probe sequence proves two whole transactions: the first mutation rolls back its row, cursor and notification; the second succeeds. Its always-fail mode proves exhaustion leaves no partial anchor, cursor or notification. Update and delete mutation paths provide the two retry-victim directions; the remaining person/beacon cascade tests honestly assert concurrent completion without claiming nondeterministic PostgreSQL lock-victim selection.
- Independently passed, one command at a time:
  - `cd packages/server && dart test test/data/database/postgres_serialization_retry_test.dart -j 1` — 5 passed.
  - `cd packages/server && dart test test/data/repository/constellation_anchor_repository_pg_test.dart -j 1` — 7 passed against a unique disposable database with in-test `SELECT current_database()` proof.
  - `cd packages/server && dart test test/data/database/constellation_anchor_storage_pg_test.dart -j 1` — 18 passed.
  - `./scripts/check-custom-lints.sh packages/server` — passed, custom-lint total 0.
- Process audit after the final worker found an orphaned task-owned repository PG test; it was terminated with `SIGTERM` and subsequent audit found no task-owned Cursor runner, Dart test/analyzer, Flutter, browser-driver, or Chrome process. Pre-existing editor/browser services remain untouched.

### P03 manager review — 2026-09-11

- Verdict: accepted. Reviewed `5ffaac2c8` and remediation `8867e7759`: the reader uses C4's top-level read-only snapshot, applies C2 filters server-side, returns residual no-path pinned Request authors without invented support edges, and shares one projection reader for FULL and ANCHORS.
- Independently passed serially: repository PG snapshot test (23), constellation selection/path/participation SQL tests, and `./scripts/check-custom-lints.sh packages/server` (custom-lint total 0).
- Post-worker process audit found no task-owned runner, Dart test/analyzer, Flutter, WebDriver, or Chrome process. Pre-existing services and untracked paths remain untouched.

### P04 manager review — 2026-09-11 (resume)

- Overseer session resumed on `feature/pin_constellation` at `e08471f98`. Worktree is clean except the original untracked docs/secrets list. Live code already owns `m0167` and exception space `1700` for this feature.
- Verdict: accepted. Reviewed `2080c78ed` / `e08471f98`. GraphQL field args, server-owned context, numeric-string codes `1700`–`1703`, and mutation result shapes match C4. No generated source or pre-existing user paths were staged.
- Independently passed: `cd packages/server && dart test test/api/controllers/graphql/constellation_anchor_test.dart -j 1` — 15 passed.
- Process audit before P05: docker has postgres + meritrank only; Hasura / tentura-server / Flutter :8888 are not running. No task-owned Cursor runner, Dart test, Flutter, WebDriver, or Chrome process. Pre-existing editor/browser services left untouched.
- Next subunit: **P05a** server echo policy only (`kRealtimeAlwaysEchoKinds` + WS protocol tests). Client GraphQL / schema_fetcher / Ferry wait for **P05b** because Hasura is down and schema fetch needs a live P04 remote schema.

### P05a — Server echo policy — 2026-09-11

- Added `kRealtimeAlwaysEchoKinds = {'constellation_anchor'}` in
  `packages/server/lib/consts/realtime_consts.dart`.
- `websocket_path_entity_changes.dart`: skip actor recipients only when echo is
  disabled **and** entity is not in `kRealtimeAlwaysEchoKinds`; recipient
  validation/stripping and thin payload shape unchanged (no `user_ids` on wire).
- WS protocol tests: `constellation_anchor` reaches both actor sessions with echo
  false and true; foreign session excluded; payload limited to
  `entity`/`id`/`event`/`actor_user_id`; existing beacon/forward echo policy
  tests unchanged.
- Commands (serial):
  - `cd packages/server && dart test test/api/controllers/websocket/websocket_realtime_protocol_test.dart` → 12 passed
  - `./scripts/check-custom-lints.sh packages/server` → exit 0

STATUS: complete

COMMITS:
- 002599c6b feat(server): always echo constellation_anchor invalidations

TESTS:
- `cd packages/server && dart test test/api/controllers/websocket/websocket_realtime_protocol_test.dart` → 12 passed
- `./scripts/check-custom-lints.sh packages/server` → exit 0

FILES:
- packages/server/lib/consts/realtime_consts.dart
- packages/server/lib/api/controllers/websocket/path_handler/websocket_path_entity_changes.dart
- packages/server/test/api/controllers/websocket/websocket_realtime_protocol_test.dart
- docs/plans/constellation-pinning-implementation-journal.md

FINDINGS:
- Echo exemption is entity-kind scoped via a const set; no env flag change needed.
- Private anchor fan-out still relies on publisher `user_ids: [viewer_id]`; the
  handler never forwards `user_ids` in the client payload.

REMAINING: P05b client GraphQL/Ferry wire adapters (schema_fetcher, repository
ports); P08 for realtime enum/manifest/contract subscriber wiring per C8.
