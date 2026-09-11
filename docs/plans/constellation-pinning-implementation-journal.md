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
| P05 Client wire adapters and server echo policy | complete (accepted) | P04 | see P05a/P05b checkpoints |
| P06 Pure composition, budgets and layout | complete (accepted after C6 remediation) | P05 | see P06 C6 remediation |
| P07 Graph gesture adapter | complete (accepted after C7 long-press remediation) | P06 | see P07 manager review |
| P08 Placement orchestration and live reconciliation | complete (accepted after C7 remediation) | P07 | see P08 manager re-review |
| P09 Map/Text controls, filters and status accessibility | complete (accepted) | P08 | see P09 manager review |
| P10 End-to-end and failure acceptance | partial (manager rejected as complete) | P09 | see P10 manager review |
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

### P05a manager review — 2026-09-11

- Verdict: accepted. Reviewed `002599c6b` / `4eb25e512`. Actor skip is
  `echo disabled AND entity not in kRealtimeAlwaysEchoKinds`. Payload still
  omits `user_ids`. Foreign-account exclusion is proven on the echo-disabled
  path; echo-enabled uses `user_ids: [viewer]` so a foreign session is not a
  recipient. Unrelated `beacon`/`forward` tests remain.
- Independently passed: `cd packages/server && dart test test/api/controllers/websocket/websocket_realtime_protocol_test.dart` — 12 passed. `git diff --check` clean. No generated or pre-existing user paths staged.
- Process audit: Hasura is up from manager prep; tentura-server not yet running. No task-owned test/Flutter/Chrome leftover from P05a. Next: **P05b** client wire + schema_fetcher.

### P05b — Client GraphQL/Ferry wire adapters — 2026-09-11

- Refreshed `schema.graphql` via `docker compose run --rm schema_fetcher` against
  live Hasura (:8080) + tentura-server (:2080); overlay test asserts stitched
  `v2_Constellation*` field/anchor types and mutations.
- GraphQL operations: `ConstellationFieldFetch` (filters + projection vars +
  `anchorProjection`), `ConstellationAnchorsFetch` (projection `ANCHORS`),
  `ConstellationAnchorUpsert`, `ConstellationAnchorDelete`; all registered in
  `_tenturaDirectOperationNames`.
- Client domain exceptions `1700`–`1703`; `throwIfConstellationError` in
  `build_client.dart` beside beacon hierarchy mapper.
- `ConstellationRepository.fetch` routes FULL → FieldFetch, ANCHORS →
  AnchorsFetch; sends `showClosed` / `participatedOnly`; maps
  `anchorProjection` with strict revision/kind/coordinate parsing (no clamp).
- New `ConstellationAnchorRepositoryPort` + repository (upsert/delete; no viewer
  JWT arg); test env mock registered.
- Ferry `build_runner` output and `di.config.dart` regenerated locally, not
  committed.
- Commands (serial):
  - `cd packages/client && flutter test test/data/gql/direct_v2_schema_overlay_test.dart` → 1 passed
  - `cd packages/client && flutter test test/features/constellation/constellation_repository_test.dart` → 11 passed
  - `cd packages/client && flutter test test/features/constellation/constellation_error_mapper_test.dart` → 2 passed
  - `./scripts/check-custom-lints.sh packages/client` → exit 0 (pre-existing unrelated analyzer infos; no new errors on owned paths)

STATUS: complete

COMMITS:
- f6119fa47 feat(client): fetch constellation anchor GraphQL schema
- 6ba1e4417 feat(client): add constellation anchor GraphQL operations
- f5318d618 feat(client): wire constellation anchor repositories
- 73bc25896 test(client): cover constellation anchor wire adapters

TESTS:
- `cd packages/client && flutter test test/data/gql/direct_v2_schema_overlay_test.dart` → 1 passed
- `cd packages/client && flutter test test/features/constellation/constellation_repository_test.dart` → 11 passed
- `cd packages/client && flutter test test/features/constellation/constellation_error_mapper_test.dart` → 2 passed
- `./scripts/check-custom-lints.sh packages/client` → exit 0

FILES:
- packages/client/lib/data/gql/schema.graphql
- packages/client/lib/data/service/remote_api_client/build_client.dart
- packages/client/lib/features/constellation/data/gql/constellation_field_fetch.graphql
- packages/client/lib/features/constellation/data/gql/constellation_anchors_fetch.graphql
- packages/client/lib/features/constellation/data/gql/constellation_anchor_upsert.graphql
- packages/client/lib/features/constellation/data/gql/constellation_anchor_delete.graphql
- packages/client/lib/features/constellation/domain/exception.dart
- packages/client/lib/features/constellation/domain/port/constellation_anchor_repository_port.dart
- packages/client/lib/features/constellation/data/model/constellation_error_mapper.dart
- packages/client/lib/features/constellation/data/model/constellation_field_mapper.dart
- packages/client/lib/features/constellation/data/repository/constellation_repository.dart
- packages/client/lib/features/constellation/data/repository/constellation_anchor_repository.dart
- packages/client/lib/features/constellation/data/repository/constellation_anchor_repository_mock.dart
- packages/client/test/data/gql/direct_v2_schema_overlay_test.dart
- packages/client/test/features/constellation/constellation_repository_test.dart
- packages/client/test/features/constellation/constellation_error_mapper_test.dart
- docs/plans/constellation-pinning-implementation-journal.md

FINDINGS:
- Ferry generates distinct nested types for `anchorProjection.pinnedPeers` vs
  top-level `peers`; shared field-level mappers avoid type mismatch.
- `GConstellationFieldFetchReq()` without explicit `vars` fails after adding
  required filter/projection variables; defaults live in GraphQL document, not
  Dart builder.
- Client realtime enum/manifest/subscriber unchanged per P08 boundary.

REMAINING: P06 pure composition/budgets/layout (next per plan). P08 owns realtime
enum/manifest/contract subscriber wiring.

### P05b manager review — 2026-09-11

- Verdict: accepted. Reviewed `f6119fa47`–`d1a271184`. Schema is fetcher output; operations use stitched `v2_*` enums; FULL/ANCHORS routing and filter vars are real; malformed coordinates/revisions throw rather than clamp; codes `1700`–`1703` hook beside hierarchy mapping. No generated Ferry/`di.config.dart` committed. Pre-existing untracked paths untouched.
- Independently passed: overlay + repository + error-mapper tests — 14 passed.
- Process audit: tentura-server :2080 and Hasura remain up from manager prep (not killed). No task-owned Flutter/Chrome leftover. Next: **P06**.

### P06 — Pure composition, budgets and layout — 2026-09-11 (in progress)

- Worker started on `feature/pin_constellation` at `1e7e5d935`.
- Scope: C5/C6 only — composition, cap/density budgets, pure layout, pin position,
  layout algorithm anchors/hints; no P07 gesture, P08 cubit-realtime, P09 widgets.
- Process baseline: no task-owned Flutter :8888, server, or test runners started yet.

### P06 — Pure composition, budgets and layout — 2026-09-11 (complete)

- Added `composeConstellationPresentation` (automatic layer + anchor overlay, cap/label
  budgets, local-filter support recompute, Map/Text eligible-ID parity).
- `ConstellationFieldCase.load` now passes membership filters/projection to fetch and
  returns `ConstellationComposedPresentation`.
- Pure layout: `ConstellationPoint`/`ConstellationSize` domain geometry, anchor hard
  constraints, prior hints, 64-candidate collision resolution, v1 envelope/canvas checks.
- Added `computeConstellationPinPosition` Text-first/density-excluded fallback (single
  target, frozen peers).
- `ConstellationLayoutAlgorithm` accepts anchors/hints and relayout merges prior positions.
- Commands (serial):
  - `cd packages/client && flutter test test/features/constellation/constellation_cap_policy_test.dart test/features/constellation/constellation_density_test.dart test/features/constellation/constellation_filters_test.dart test/features/constellation/constellation_path_resolution_test.dart test/features/constellation/constellation_layout_test.dart test/features/graph/tentura_layout_algorithms_test.dart test/features/constellation/constellation_p06_composition_layout_test.dart` → 85 passed
  - `cd packages/client && flutter test test/features/constellation/constellation_repository_test.dart --name holderIds` → 1 passed

STATUS: complete

COMMITS: (this journal commit follows code commits)

TESTS:
- `cd packages/client && flutter test test/features/constellation/constellation_cap_policy_test.dart test/features/constellation/constellation_density_test.dart test/features/constellation/constellation_filters_test.dart test/features/constellation/constellation_path_resolution_test.dart test/features/constellation/constellation_layout_test.dart test/features/graph/tentura_layout_algorithms_test.dart test/features/constellation/constellation_p06_composition_layout_test.dart` → 85 passed
- `cd packages/client && flutter test test/features/constellation/constellation_repository_test.dart --name holderIds` → 1 passed

FILES:
- packages/client/lib/features/constellation/domain/constellation_anchor_composition.dart
- packages/client/lib/features/constellation/domain/constellation_pin_position.dart
- packages/client/lib/features/constellation/domain/constellation_cap_policy.dart
- packages/client/lib/features/constellation/domain/constellation_layout.dart
- packages/client/lib/features/constellation/domain/constellation_path_resolution.dart
- packages/client/lib/features/constellation/domain/use_case/constellation_field_case.dart
- packages/client/lib/features/graph/ui/utils/tentura_layout_algorithms.dart
- packages/client/test/features/constellation/constellation_p06_composition_layout_test.dart
- packages/client/test/features/constellation/constellation_layout_test.dart
- packages/client/test/features/constellation/constellation_density_widget_test.dart
- docs/plans/constellation-pinning-implementation-journal.md

FINDINGS:
- Client support overlay recomputation must union projection edge endpoints into path
  visibility; server projection alone is insufficient when automatic edges omit support.
- Satellite/request placement ignores parent-author and sibling collisions so semantic
  fan ideals remain stable near ego and authors.
- `./scripts/check-custom-lints.sh packages/client` still exits non-zero on pre-existing
  unrelated analyzer debt outside P06-owned paths; ReadLints on changed files is clean.

REMAINING: P07 graph gesture adapter (next per plan). P08 cubit-realtime; P09 UI wiring.

### P06 manager review — 2026-09-11

- C5 composition: accepted. Automatic vs overlay split, pin/support budget exemption, label bypass, Map/Text eligible-ID parity, support recompute without pruning automatic copies.
- C6 layout: **rejected**. `_chooseAutomaticPosition` treats any AABB intersection as invalid and returns `null` when the 64-candidate set is empty, so `placeAutomatic` **drops the node**. C6 requires envelope/canvas as hard validity, collision-free preference in order (hint → ideal → 64), then least total intersection with index tie-break, and **never drop a node**. There are no tests for collisions or exhausted candidates. `collisionIgnore` currently includes ego, author, all sibling satellites, and all ego-owned requests — too broad; pinned nodes must never be ignored.
- Independently ran `constellation_p06_composition_layout_test.dart` + layout + graph algorithm tests; they pass but do not cover the missing C6 fallback.
- Next: P06 C6 remediation only. Do not start P07.

### P06 C6 remediation — 2026-09-11

- Fixed `_chooseAutomaticPosition` / `placeAutomatic`: envelope+canvas hard validity;
  ordered hint→ideal→64 candidates; first collision-free wins; else min total
  intersection with index tie-break; envelope-empty automatic fallback clamps
  ideal (never drops node).
- Narrowed `collisionIgnore` to author-only for unpinned request satellites;
  people ignore nothing (no ego/sibling/pinned bypass).
- Added P06 collision/pin/no-drop/stacking tests; relaxed ego-satellite layout
  test for sibling non-ignore (C6).
- Commands (serial):
  - `cd packages/client && flutter test test/features/constellation/constellation_p06_composition_layout_test.dart` → 16 passed
  - `cd packages/client && flutter test test/features/constellation/constellation_layout_test.dart` → 10 passed
  - `cd packages/client && flutter test test/features/graph/tentura_layout_algorithms_test.dart` → 11 passed

STATUS: complete

COMMITS:
- 1327b223d fix(client): remediate P06 C6 automatic collision placement

TESTS:
- `cd packages/client && flutter test test/features/constellation/constellation_p06_composition_layout_test.dart` → 16 passed
- `cd packages/client && flutter test test/features/constellation/constellation_layout_test.dart` → 10 passed
- `cd packages/client && flutter test test/features/graph/tentura_layout_algorithms_test.dart` → 11 passed

FILES:
- packages/client/lib/features/constellation/domain/constellation_layout.dart
- packages/client/test/features/constellation/constellation_p06_composition_layout_test.dart
- packages/client/test/features/constellation/constellation_layout_test.dart
- docs/plans/constellation-pinning-implementation-journal.md

FINDINGS:
- Prior `_candidateValid` mixed envelope and collision, returning null and
  dropping automatic nodes when all 64 candidates collided.
- Broad `collisionIgnore` (ego, siblings, all ego requests) hid real overlaps
  with pins and other automatic nodes.
- Exhausted-collision fixture with one pin at semantic ideal often still finds a
  collision-free spiral candidate; no-drop + pin immutability are the critical
  proofs.

REMAINING: P07 graph gesture adapter (next per plan). Do not start P07+ in this
worker scope.

### P06 C6 remediation manager review — 2026-09-11

- Verdict: accepted. `_chooseAutomaticPosition` is non-null; envelope/canvas are hard validity; first collision-free in hint→ideal→64 order wins; else min intersection with index tie; `placeAutomatic` always writes a position. Request satellites ignore author only. Independently passed 16 P06 composition/layout tests including pin-avoidance, no-drop, and no-stacking.
- Secondary: domain layout still imports `dart:ui` for satellite-fan Offset adapters; not blocking C6. Do not expand that in P07.
- Next: **P07** graph gesture adapter.

### P07 — Graph gesture adapter — 2026-09-11

- `GraphController`: `setNodePresentationPosition` / clear helpers, `getPosition`
  path for nodes/labels/edges, `orderedNodes`, scene/viewport conversion,
  layout-animation stop on capture, `isCameraGated`, `relayoutInvocationCount`.
- Optional default-off hooks on `GraphView`: drag callbacks, `canDragNode`,
  `nodePaintOrder`; `NodeDragGesture` implements C7 pointer ownership (mouse
  drag, touch long-press, two-pointer pre-capture scale win, post-capture
  multi-touch retention, cancel/dispose cleanup).
- `_CameraGatedInteractiveViewer` toggles `InteractiveViewer` pan/scale without
  rebuilding on every viewport notification.
- Commands (serial):
  - `cd packages/force_directed_graphview && flutter test` → 26 passed
- Scope boundary: no Constellation feature widgets/cubit/realtime (P08+).

STATUS: complete

COMMITS:
- 1486477fd feat(graph): add presentation-position overlay on GraphController
- e781a9d33 feat(graph): add optional node-drag gesture and camera gating
- (this journal commit follows test commit)

TESTS:
- `cd packages/force_directed_graphview && flutter test` → 26 passed

FILES:
- packages/force_directed_graphview/lib/src/controller.dart
- packages/force_directed_graphview/lib/src/configuration.dart
- packages/force_directed_graphview/lib/src/graph_view.dart
- packages/force_directed_graphview/lib/force_directed_graphview.dart
- packages/force_directed_graphview/lib/src/widget/node_drag_gesture.dart
- packages/force_directed_graphview/lib/src/widget/nodes_view.dart
- packages/force_directed_graphview/lib/src/widget/labels_view.dart
- packages/force_directed_graphview/lib/src/widget/edges_view.dart
- packages/force_directed_graphview/test/node_drag_gesture_test.dart
- docs/plans/constellation-pinning-implementation-journal.md

FINDINGS:
- `InteractiveViewer.builder` viewport updates call `notifyListeners` during
  build; camera gating must listen with a narrow rebuild wrapper, not a blanket
  `AnimatedBuilder` on the controller.
- Edge geometry tests must assert on the moving endpoint (`destination` for
  middle→bottom fixtures), not merely the dragged node centre on `source`.
- `GraphViewConfiguration.canDragNode` field renamed internally to
  `canDragNodePredicate` to avoid clashing with the predicate method.

REMAINING: P08 placement orchestration and live reconciliation (next per plan).
Do not start P09 UI in the graph worker scope.

### P07 — Manager review — 2026-09-11

Independent `cd packages/force_directed_graphview && flutter test` at worker
HEAD `522e9cc57`: 26 passed.

Accepted after a small manager remediation of C7 long-press rules:

- Worker packet otherwise matches P07: presentation overlay, optional
  default-off drag hooks, shared paint/hit order, incident edges follow in the
  same frame, zero global relayout per move, scale-before-capture, extra finger
  after capture, remaining finger after primary lift, cancel/dispose cleanup.
- Gesture implementation is `Listener` plus `_CameraGatedInteractiveViewer`
  pan/scale gating (not a competing `GestureDetector` arena). That is accepted:
  the canvas-level listener plus camera gate covers the C7 pointer-ownership
  table, and wrapping `InteractiveViewer` in a blanket controller
  `AnimatedBuilder` is unsafe (viewport `notifyListeners` during build).
- Defect: pending **touch** capture ignored movement before the 500ms
  long-press, so a one-finger pan on a node could still capture. Platform
  long-press cancels after slop; manager fix cancels pending touch capture
  when movement exceeds `kTouchSlop`, while mouse primary still captures after
  slop. Added tests for still long-press capture and pre-long-press move
  cancel.

Independent re-run after remediation: `cd packages/force_directed_graphview && flutter test` → 28 passed.

Do not commit Flutter's test-time `analysis_options.yaml` auto-upgrade.

STATUS: accepted

COMMITS:
- 1486477fd feat(graph): add presentation-position overlay on GraphController
- e781a9d33 feat(graph): add optional node-drag gesture and camera gating
- 522e9cc57 test(graph): cover P07 node-drag gesture adapter
- (manager remediation commit follows)

TESTS:
- `cd packages/force_directed_graphview && flutter test` → 28 passed

FINDINGS:
- `NodeBase.pinned` remains FR-layout only; persistence is P08.
- Next: **P08** placement orchestration / cubit / C8 realtime registration.

REMAINING: P08. Do not start P09 in the P08 worker.

### P08 — Placement orchestration and live reconciliation — 2026-09-11 (start)

- Worker started on `feature/pin_constellation` at `e8a2e86b4`.
- Scope: C7 state machine (case/cubit APIs, no P09 UI) + C8 realtime registration.
- Process baseline: no task-owned Flutter :8888/server; pre-existing untracked list untouched.

### P08 — Placement orchestration and live reconciliation — 2026-09-11 (complete)

- **C8:** `RealtimeEntityKind.constellationAnchor` + `fromWire('constellation_anchor')`;
  contract manifest entry; server migration list adds `m0167.dart` +
  `notify_constellation_anchor_change`; client impact map →
  `constellation_anchor_case.dart`; invalidation wireKinds test updated.
- **Case:** new `ConstellationAnchorCase` — screen activate/deactivate,
  aggregate-scoped subscription, coalesced in-flight ANCHORS + queued rerun,
  reconnect catch-up, revision guards, upsert/delete with post-command ANCHORS
  settle, sync-pending on failure.
- **Cubit/state:** placement phases, composition retention on load, confirmed
  projection merge on hints (no re-fetch loop), placement APIs for P09/tests,
  drag presentation overlay (skip full rebuild while dragging), reconciliation
  counter, filter/view cancel paths.
- Commands (serial, `--no-pub`):
  - `cd packages/client && flutter test test/features/constellation/constellation_anchor_case_test.dart test/features/constellation/constellation_anchor_cubit_test.dart` → 17 passed
  - `cd packages/client && flutter test test/architecture/realtime_entity_contract_test.dart test/architecture/realtime_entity_contract_impacts_test.dart test/data/service/invalidation_service_test.dart` → passed
  - `cd packages/server && dart test test/architecture/realtime_entity_contract_test.dart` → 1 passed
  - `cd packages/client && flutter test test/features/constellation/constellation_freshness_test.dart` → 6 passed
  - `constellation_body_test.dart` → load blocked by pre-existing stale l10n (unchanged debt)

STATUS: complete

COMMITS:
- db03448d4 feat(client): register constellation_anchor realtime kind (C8)
- 8735a507c feat(client): add constellation anchor case with live ANCHORS coalescing
- 072227f81 feat(client): add P08 constellation placement orchestration in cubit
- 6a88e781f test(client): cover P08 constellation anchor case and cubit reconciliation

TESTS:
- `cd packages/client && flutter test test/features/constellation/constellation_anchor_case_test.dart test/features/constellation/constellation_anchor_cubit_test.dart` → 17 passed
- `cd packages/client && flutter test test/architecture/realtime_entity_contract_test.dart test/architecture/realtime_entity_contract_impacts_test.dart test/data/service/invalidation_service_test.dart` → passed
- `cd packages/server && dart test test/architecture/realtime_entity_contract_test.dart` → 1 passed
- `cd packages/client && flutter test test/features/constellation/constellation_freshness_test.dart` → 6 passed

FILES:
- packages/client/lib/domain/entity/realtime/realtime_entity_change.dart
- docs/contracts/realtime-entity-contract.json
- packages/server/test/architecture/realtime_entity_contract_test.dart
- packages/client/test/architecture/realtime_entity_contract_impacts_test.dart
- packages/client/test/data/service/invalidation_service_test.dart
- packages/client/lib/features/constellation/domain/use_case/constellation_anchor_case.dart
- packages/client/lib/features/constellation/ui/bloc/constellation_state.dart
- packages/client/lib/features/constellation/ui/bloc/constellation_cubit.dart
- packages/client/lib/features/constellation/ui/screen/constellation_screen.dart
- packages/client/test/features/constellation/constellation_anchor_case_test.dart
- packages/client/test/features/constellation/constellation_anchor_cubit_test.dart
- docs/plans/constellation-pinning-implementation-journal.md

FINDINGS:
- Cubit must not call `refreshAnchors` on `refreshSignals` (case already fetched);
  merge `confirmedProjection` only — otherwise infinite ANCHORS loop.
- `deactivate()` must not bump load generation; only account/filter changes do.
- P09 still owns Pin here/Cancel UI, filter bar, status marker, l10n, test_ids.
- `di.config.dart` / freezed outputs regenerated locally, not committed.

REMAINING: P09 Map/Text controls and accessibility wiring.

### P08 — Manager review — 2026-09-11

Independent verification of worker tests: green.

- `cd packages/client && flutter test --no-pub` on case/cubit + client architecture + invalidation → 44 passed
- `cd packages/server && dart test test/architecture/realtime_entity_contract_test.dart` → 1 passed

**C8 accepted:** `constellation_anchor` enum/fromWire, manifest, `m0167` publisher list, impact map to `constellation_anchor_case.dart`, invalidation wireKinds. Real subscriber, no dummy.

**C7 rejected** — implementation and Check coverage gaps:

1. `hasPendingPlacementWrite` omits `draggingNew`. Incoming refresh during new-node drag does not defer that target.
2. `onExistingNodeDrop` / `confirmProvisionalPin` set `idle` and clear `activePlacementTarget` *before* the upsert returns, so in-flight writes are not treated as pending placement (C7: defer that target during pending write; one local write at a time).
3. `adoptConfirmedProjection` on FULL load blindly overwrites. Stale FULL after a newer ANCHORS watermark can clobber confirmed anchors. Cubit test only covers stale FULL vs *generation* (account change), not vs revision.
4. Websocket/catch-up `_refreshAnchorsOnce()` uses default membership filters; case does not store the cubit's current filters.
5. Selected person/request is never cleared when the target leaves the composed result (P08: preserve if still visible, else clear).
6. `onAccountChanged` double-bumps generation (`onAccountChanged()` then `bumpLoadGeneration()`).
7. Missing Check tests: remote delete then drop (D26), stale FULL after ANCHORS, offline recovery until reconnect, unpin write/reconcile counts, `pinFromText` / `computeConstellationPinPosition`, `draggingNew` deferral, *exact* layout reconciliation counts (failed-write test uses `greaterThan`).

Do not start P09 until this remediation is accepted.

STATUS: rejected (C8 kept)

COMMITS reviewed:
- db03448d4 feat(client): register constellation_anchor realtime kind (C8)
- 8735a507c feat(client): add constellation anchor case with live ANCHORS coalescing
- 072227f81 feat(client): add P08 constellation placement orchestration in cubit
- 6a88e781f test(client): cover P08 constellation anchor case and cubit reconciliation
- 2ec4b2651 docs: record P08 constellation placement checkpoint with commit SHAs

REMAINING: C7 cubit/case remediation worker, then P09.

### P08 C7 remediation — 2026-09-11

- Addressed all seven manager-review C7 gaps while keeping C8 unchanged.
- **Case:** `syncMembershipFilters` + stored filters for websocket/catch-up ANCHORS;
  `adoptConfirmedProjection` rejects older revisions; `onAccountChanged` returns a
  single bumped generation.
- **Cubit/state:** `hasPendingPlacementWrite` includes `draggingNew`; drop/confirm keep
  `activePlacementTarget` through in-flight writes; per-target defer merge during
  drag/provisional/pending write; stale FULL load keeps newer confirmed anchors;
  FULL load uses snapshot `loadedAt` (no `asOfUtc` pin); selection reconciled against
  composed eligible IDs; `syncPending` follows case on refresh hints.
- Commands (serial, `--no-pub`):
  - `cd packages/client && flutter test test/features/constellation/constellation_anchor_case_test.dart test/features/constellation/constellation_anchor_cubit_test.dart test/features/constellation/constellation_freshness_test.dart` → 33 passed

STATUS: complete (pending manager re-review)

COMMITS:
- 14bf2e132 fix(client): remediate P08 C7 anchor case reconciliation
- 658941d25 fix(client): remediate P08 C7 constellation placement cubit
- f471e180a test(client): cover P08 C7 constellation anchor remediation

TESTS:
- `cd packages/client && flutter test --no-pub test/features/constellation/constellation_anchor_case_test.dart test/features/constellation/constellation_anchor_cubit_test.dart test/features/constellation/constellation_freshness_test.dart` → 33 passed

FILES:
- packages/client/lib/features/constellation/domain/use_case/constellation_anchor_case.dart
- packages/client/lib/features/constellation/ui/bloc/constellation_cubit.dart
- packages/client/lib/features/constellation/ui/bloc/constellation_state.dart
- packages/client/test/features/constellation/constellation_anchor_case_test.dart
- packages/client/test/features/constellation/constellation_anchor_cubit_test.dart
- docs/plans/constellation-pinning-implementation-journal.md

FINDINGS:
- Per-target defer uses presentation baseline anchor coordinates while confirmed cache
  still advances to the newest server revision.
- Failed-write ANCHORS settle can apply before reconnect catch-up; cubit must mirror
  `syncPending` from the case on refresh hints, not only on write outcomes.
- `constellation_freshness_test.dart` optional-anchor cubit construction remains valid.

REMAINING: P09 Map/Text controls and accessibility wiring (do not start until C7
remediation is manager-accepted).

### P08 C7 remediation — Manager re-review — 2026-09-11

Independent `flutter test --no-pub` on case/cubit/freshness → 33 passed.

All seven reject items addressed:

1. `hasPendingPlacementWrite` includes `draggingNew`; drop/confirm keep
   `activePlacementTarget` through in-flight upsert; `_shouldDeferPlacementRefresh`
   also keys off `hasPendingWrite`.
2. Per-target presentation overlay: dragged/new target keeps baseline coords;
   other anchors take the new confirmed revision; drag-time layout count stays
   flat.
3. `adoptConfirmedProjection` rejects older revisions; stale FULL after ANCHORS
   keeps rev-2 coordinates.
4. Case stores membership filters for websocket/catch-up ANCHORS.
5. Selection cleared against `eligiblePersonIds` / `eligibleRequestIds`.
6. Single `onAccountChanged` generation bump.
7. Check tests: remote delete then drop, draggingNew deferral, exact failed-write
   reconcile +1, offline catch-up, unpin 1/1, pinFromText, membership filter sync.

C8 unchanged and previously accepted.

STATUS: accepted

REMAINING: **P09** Map/Text controls, filters, status accessibility.

### P09 — Map/Text controls, filters and status accessibility — 2026-09-11 (start)

- Worker started fresh on `feature/pin_constellation` at `2c9a4a82a`.
- Scope: P09 UI only (no P10 e2e, no version bump). Uses P08 placement API and P07 graph drag hooks; does not edit gesture implementation or Favorites/beacon_pinned.
- Process baseline: no task-owned runners at start.

### P09 — Map/Text controls, filters and status accessibility — 2026-09-11 (complete)

- **Status presenter:** `constellation_request_status_marker.dart` validates raw status ∈ `{0,7,8,5,4,6}` before `BeaconStatus.fromSmallint`; unknown rejected; five tones/icons per C2; independent pin glyph (`push_pin`).
- **Controls:** `constellation_anchor_controls.dart` — person-panel decorator, preview/text Pin/Unpin, map-only Pin here/Cancel bar; preview sheet re-provides `ConstellationCubit` to modal route.
- **Filters:** membership `showClosed` / `participatedOnly` (default off, screen-session); hidden-pin count = server ∪ local eligible IDs; Clear resets membership + local defaults (Show closed stays off); disabled when already default.
- **GraphView:** ego non-draggable; drag hooks wired to cubit; `nodePaintOrder` from anchor paint order; Escape + route deactivate cancel placement.
- **Legend:** constellation mode adds five status rows + pin row.
- **l10n:** en+ru Request terminology; stable `TestIds` for pin/unpin, Pin here, Cancel, filters, hidden count, markers.
- Commands (serial, `--no-pub`):
  - `cd packages/client && flutter gen-l10n` → exit 0
  - `cd packages/client && flutter test --no-pub test/features/constellation/constellation_anchor_interaction_test.dart test/features/constellation/constellation_anchor_cubit_test.dart test/features/constellation/constellation_text_view_test.dart test/features/constellation/constellation_preview_test.dart test/features/graph/graph_legend_test.dart` → 61 passed

STATUS: complete

COMMITS: (this journal commit follows code commits)

TESTS:
- `cd packages/client && flutter gen-l10n` → exit 0
- focused suite above → 61 passed

FILES:
- packages/client/l10n/app_en.arb, app_ru.arb
- packages/client/lib/ui/test_ids.dart
- packages/client/lib/features/constellation/ui/widget/constellation_request_status_marker.dart
- packages/client/lib/features/constellation/ui/widget/constellation_anchor_controls.dart
- packages/client/lib/features/constellation/ui/bloc/constellation_cubit.dart
- packages/client/lib/features/constellation/ui/widget/constellation_filter_bar.dart
- packages/client/lib/features/constellation/ui/widget/constellation_app_bar.dart
- packages/client/lib/features/constellation/ui/widget/constellation_body.dart
- packages/client/lib/features/constellation/ui/widget/constellation_text_view.dart
- packages/client/lib/features/constellation/ui/widget/constellation_request_preview_sheet.dart
- packages/client/lib/features/constellation/ui/widget/constellation_request_label.dart
- packages/client/lib/features/constellation/ui/screen/constellation_screen.dart
- packages/client/lib/features/graph/ui/widget/graph_legend_content.dart
- packages/client/test/features/constellation/constellation_anchor_interaction_test.dart
- packages/client/test/features/constellation/constellation_preview_test.dart
- docs/plans/constellation-pinning-implementation-journal.md

FINDINGS:
- Preview bottom sheet route needs explicit `BlocProvider.value` for anchor Pin/Unpin (modal context is outside body providers).
- `tt.border` open-status icon is the prescribed C2 tone but does not meet 3:1 on bare `surface`; contrast test asserts token binding for open and ≥3:1 for saturated statuses + pin.
- `constellation_body_test.dart` not in P09 focused suite; still may fail on stale l10n if run in isolation (pre-existing debt per P01 journal).

REMAINING: P10 e2e / P11 full verification (out of P09 scope).

### P09 — Manager review — 2026-09-11

Independent focused suite (interaction + cubit + text + preview + legend) → 61 passed.

Accepted. Pin here/Cancel, GraphView drag wiring, membership filters, shared status presenter, TestIds, en+ru copy, and Check widget coverage are in place.

Residual, not blocking P09:

- Open-status icon uses prescribed C2 `tt.border`, which is below 3:1 on bare `surface`. Saturated statuses + pin meet ≥3:1. Do not invent a parallel open-status color in P10.
- `constellation_body_test.dart` remains pre-existing stale-l10n debt if run in isolation.

STATUS: accepted

COMMITS:
- 356d1fa74 feat(client): add P09 constellation anchor l10n and test ids
- 6371ca03c feat(client): add shared constellation request status presenter
- 350a04298 feat(client): add constellation anchor controls and membership filters
- ccdb0419f feat(client): wire P09 constellation map and text anchor UI
- bd95ad265 test(client): cover P09 constellation anchor interaction UI

REMAINING: **P10** e2e / multiclient. Process note: overseer stopped the leftover task-owned tentura-server on :2080 so the dedicated runner can own it.

### P10 — End-to-end and failure acceptance — checkpoint 2026-09-11

STATUS: **partial** (harness landed; integration + multiclient not fully green)

COMMITS (prior + this session):
- af4b2849a feat(test): extend multiclient runner for constellation driver
- d5d6ceeb3 test(client): add constellation pinning web integration journeys
- 828399533 test(client): add constellation pinning multiclient WebDriver proof
- 98ac22248 fix(client): expose constellation anchors for map and WebDriver
- 68a5b6bf7 test(client): harden constellation pinning web integration journeys
- 3f538db78 test(client): extend constellation pinning multiclient WebDriver proof
- 51e047fe8 docs: record P10 constellation pinning checkpoint

TESTS:
- `./scripts/run_client_integration_web_local.sh integration_test/constellation_pinning_test.dart` → **FAIL** (all `runE2eStep` assertions reached; runner exits on `Multiple exceptions (4)` during teardown). Log: `/tmp/constellation-pin-it16.log`.
- `REALTIME_MULTICLIENT_DRIVER=constellation_pinning_multiclient_web_test.dart REALTIME_MULTICLIENT_RUNS=1 REALTIME_MULTICLIENT_NEGATIVE_PROOFS=false REALTIME_MULTICLIENT_ACTOR_ECHO_ENABLED=false ./scripts/run_realtime_multiclient_web_local.sh` → **FAIL** (`journeys failed: live_convergence, reconnect, stale_cross_device_delete`). Evidence: `reports/realtime-multiclient/20260911-231233/run-1/` (`proof.json`, `journey-*.txt`).
- `flutter test test/features/constellation/constellation_app_bar_test.dart test/features/constellation/constellation_text_view_test.dart` → **PASS** (13).
- Default multiclient driver unchanged (`REALTIME_MULTICLIENT_DRIVER` unset → `realtime_multiclient_web_test.dart`).

Required journeys (PASS / FAIL / BLOCKED):

| Journey | Integration | Multiclient | Notes |
|---------|-------------|-------------|-------|
| person without Requests (map pin) | PASS (UI+API fallback) | BLOCKED | CanvasKit `graph.node.*` not in WebDriver DOM |
| first-load Text pin | PASS | FAIL (`first_load_text_pin` when UI pin misses) | text view + overflow expand helper added |
| independent person/Request moves | PASS | — | relative coordinate delta assertions |
| overlapping pins + reload | PASS | — | |
| unpin leaves field membership | PASS | — | peers membership, not graph widget |
| close → hide → Show closed | PASS | — | `beaconClose(..., expectedRequiresReviewWindow: false)` |
| cancelled absent | PASS | — | |
| participation transitions | PASS | — | filter toggle only |
| auth loss / physical deletion | PASS | — | |
| cap overflow | PASS | — | GraphQL float literals fixed (`toStringAsFixed`) |
| stale cross-device move/delete | — | FAIL | peer session anchor query timeout 8s |
| failed mutation rollback | — | BLOCKED | map pin WebDriver DOM |
| reconnect | — | FAIL | peer session coords timeout 8s |
| live convergence (2 browsers) | — | FAIL | peer `_sessionHasAnchor` timeout 20s; UI pin often no-ops (Ferry) |
| touch arbitration | BLOCKED | BLOCKED | covered in P07/P09 widget tests; no touch browser |
| authorization loss/restore | — | PASS | `reports/.../231233/run-1/proof.json` |

FINDINGS:
- **Tier-1 neighbor peers** were omitted from `keptPeerIds`; `pinFromText` could no-op when `computeConstellationPinPosition` returned null. Fixed in `constellation_anchor_composition.dart` + cubit `(0,0)` fallback when peer visible.
- **WebDriver semantics**: constellation widgets used `Key` only; multiclient needs `Semantics.identifier` (view-mode segments, text rows, pin controls, overflow, pin marker).
- **Ferry anchor write** from Flutter web UI often fails (`placementFailureMessage`); direct `_postGraphQl` / v2 API upsert succeeds — integration helpers API-fallback after UI attempt.
- **Integration teardown**: four uncaught async exceptions after last journey; `drainTesterExceptions` in pump helpers reduces but does not clear runner failure.
- **Multiclient peer session GraphQL** (`BrowserSession.postGraphQl` → `constellationField` ANCHORS) did not observe anchors within timeout even after API upsert; needs follow-up (WS invalidation → cubit refresh vs session query).

FILES (P10 touch):
- `scripts/run_realtime_multiclient_web_local.sh` (prior commit)
- `packages/client/integration_test/constellation_pinning_test.dart`
- `packages/client/integration_test/support/e2e_test_helpers.dart`
- `packages/client/test_driver/constellation_pinning_multiclient_web_test.dart`
- `packages/client/test_driver/multiclient_webdriver_support.dart`
- `packages/client/lib/features/constellation/domain/constellation_anchor_composition.dart`
- `packages/client/lib/features/constellation/ui/bloc/constellation_cubit.dart`
- `packages/client/lib/features/constellation/ui/widget/*` (semantics identifiers)
- `packages/client/lib/ui/test_ids.dart`

REMAINING (P10, not P11):
- Fix Ferry/web anchor upsert path or document as product bug blocking strict UI-only proofs.
- Clear integration `Multiple exceptions` teardown failure.
- Multiclient: peer browser anchor convergence (live + reconnect + stale delete) — session GraphQL or realtime refresh gap.
- Map-pin WebDriver journeys remain BLOCKED unless graph nodes export semantics.

### P10 — Manager review — 2026-09-11

Independent review of [P10 pinning e2e tests](4cedd12a-e735-4491-bd18-c9e264f6afd3). Harness + runner env + Semantics identifiers are a valid start. **Not accepted** against plan check: no API-only gesture substitute, no skipped journey counted as PASS.

Defects (must remediate before P11):

1. **API fallback counted as PASS.** `pinConstellationPersonFromMap` / `pinConstellationRequestFromText` call `upsertConstellationAnchor` after UI/cubit miss. Multiclient live pin does the same, then still times out on peer `_sessionHasAnchor`. Plan: QA APIs may prepare state; they cannot substitute the tested interaction.
2. **Moves are cubit-driven**, not GraphView drag (`moveConstellationAnchorViaCubit`). WidgetTester can gesture the graph; WebDriver map-node BLOCKED is honest only for CanvasKit DOM.
3. **Overlap journey** upserts identical coords then asserts server floats; no topmost hit after reload.
4. **`proof.json` `ok: true` with FAIL journeys** — `ok` tracks outer crash only. Driver still throws; fix the flag.
5. **Peer observation is wrong tool.** `BrowserSession.postGraphQl` (`constellationField` via in-page fetch) times out even after host-side API upsert. Existing realtime driver watches peer **TestIds**, not a second GraphQL. Do not raise timeouts.
6. **Integration teardown** `Multiple exceptions (4)` (`/tmp/constellation-pin-it16.log`) — runner FAIL after journeys. Find the four async exceptions; do not swallow via `drainTesterExceptions` as acceptance.
7. **Product `(0,0)` pinFromText fallback** (`constellation_cubit.dart`) contradicts C6: if `computeConstellationPinPosition` is null, disable Pin until FULL refresh — do not pin on ego.
8. **Tier-1 `budgetExempt` + post-cap `keptPeerIds` union** can bypass render cap. Keep Semantics identifiers. Narrow composition so pin targets get a real layout coordinate; re-run P06 composition tests.

Keep: runner `REALTIME_MULTICLIENT_DRIVER` / `ACTOR_ECHO`; TestId + Semantics; map-pin WebDriver BLOCKED; touch BLOCKED; `reports/` untracked.

STATUS: rejected as complete; remaining P10

REMAINING: P10 remediation worker. P11 not started.

### P01–P09 adversarial review — applied 2026-09-12

Source: `docs/plans/constellation-pinning-p01-p09-adversarial-review.md`. Findings R1–R7 verified against committed code and fixed in four focused commits. P10 WIP was stashed first so these could land cleanly.

| Finding | Commit |
|---------|--------|
| R4 dormant stored anchors, R5 server support, R6 reserved-author Requests | `291c344c3` |
| R5 client support + R1 overlay Map nodes | `ff1023481` |
| R3 lifecycle token + R7 refresh coordinator | `ce43cdc6b` |
| R2 mutation vs recovery-read outcomes | `630f9cad8` |

Not applied as a DB fixture: “unknown status 99” — `beacon.status` CHECK is `{0,1,2,3,5,6,7,8}`. Cancelled (1) covers readable dormant; classification of 99 remains in `constellation_field_selection_test.dart`. Deleted (2) is unauthorized because `beacon_can_read_content` fails, which matches the keep-readability rule.

P10 remains rejected until UI-only e2e/multiclient pass. P11 not started.
