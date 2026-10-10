# Constellation always-interactive: implementation plan (issue #235)

Status: **rev 6**, 2026-10-10. Derived from `issue-235-constellation-interactive-architecture.md` **rev 10**, which is binding. Rev 6 applies owner decisions **D9–D15** (speculative lazy writes, ack-only apply without visibility authorization, no support-closure fetch on pin, speculative graph trust changes, timeout notice, pin beats visibility but not blocks). It adds units **U50–U54** and amends U13, U21–U26, U29, U40, U41 and U46; each amendment is marked **Rev 6** in place, and the summary is under "Rev 6 additions" below.

Rev 5 (2026-10-06) (measurement run 4): U47 becomes walks-cache sizing (Tentura config, release precondition), and U48 becomes optional. A MeritRank generation-checked reverse-score cache is done separately in `meritrank-rust`, outside this plan. D8 is confirmed. Rev 4 rewrites U45 as adoption of the shipped connector (pgmer2 0.8.3), adds U47 (MR score performance, external) and U48 (cross-request visible-set cache), and points U41 at the prepared local datasets.

- Rev 2 added the server-performance units U41–U44, plus perf gates.
- Rev 3 adds U45 (MR connector deadlines, in the `meritrank-rust` repo) and U46 (frozen RR visibility memo), and tightens U09, U10, U11, U13, U15, U21, U23, U26, U41, U42 and U43. Cited as **ARCH §x**; owner decisions are **D1–D15** (D9–D15 since rev 6), invariants **I1–I6** and outbox rules **R1–R9**.

Review history is in `issue-235-constellation-interactive-review-record.md`. Execution journal: `issue-235-constellation-interactive-journal.md`, created by U00.

## Global constraints

- **Branch:** `feature/issue-235-interactive-constellation`. One focused commit per unit, message `…(constellation): … (#235 Uxx)`.
- **Layers:** follow `.cursor/rules/architecture.mdc` and the `clean-architecture` skill. Domain stays pure (no Flutter, no `dart:ui`, no Ferry). Cubits use cases only. Server domain → ports only.
- **UI work** goes through the `material-3-flutter` skill and design-system tokens. All copy goes through l10n (`packages/client/l10n/*.arb`). User-facing terms are **Request** / **Chat**.
- **Codegen:** never edit generated files. Run `build_runner` after Freezed, Ferry or Injectable changes. Refresh the client schema before Ferry codegen (Ferry consumes the checked-in schema, `packages/client/build.yaml:32`).
- **Migrations:** new files only, taking the next free numbers at implementation time (the unit titles say m0224–m0226, but other work may take numbers first), each registered in `_migrations.dart` (part list plus registry). Never edit a merged migration.
- **Tests:**
  - Structural only, never goldens. Every run goes through `scripts/run_with_test_cleanup.sh`, **serially**; two wrapped runs sweep each other's kernels.
  - pg tests: `-x pg` excluded locally unless the unit needs them. pg tests must not query `pg_locks` unscoped.
- **Lints:** `./scripts/run_with_test_cleanup.sh --timeout 10m -- ./scripts/check-custom-lints.sh packages/{client,server}` must stay at or below the baseline (re-read `scripts/custom-lint-baseline.txt`).
- **Formatting:** `dart format` only on touched files.
- **Release gate:** the protocol switch ships in one release: client semver, `web/index.html` cache-buster, `kDefaultMinClientVersion` (U26). No legacy-client support.
- **D3 ordering:** no render-layering unit (U34+) starts before U26 lands.

## Executor contract

Each unit:
1. reads its ARCH sections;
2. writes failing tests first where a test is listed;
3. implements;
4. runs the listed verification;
5. appends a journal entry `## UNIT Uxx — complete|partial|blocked — <ISO date>`, covering what changed, test counts, deviations and follow-ups;
6. commits.

A unit whose acceptance can't be met stops and records **blocked** with the evidence. It never weakens a test to pass.

**Verification shorthand**
- **CT** = `cd packages/client && ../../scripts/run_with_test_cleanup.sh --timeout 45m -- flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env <paths>`
- **ST** = `cd packages/server && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- dart test <paths>`. Add `-t pg` for pg units after the documented two-step pg setup in AGENTS.md § Verify.
- **PT** = `cd packages/force_directed_graphview && ../../scripts/run_with_test_cleanup.sh --timeout 20m -- flutter test`
- **LINT** = custom lints for the touched package(s).

## Unit manifest

| Phase | Units | Theme | Depends |
|---|---|---|---|
| P0 | U00–U01 | Baseline, journal, instrumentation and benchmark fixture | — |
| P1 | U02–U09 | Purity and splits, no behaviour change (except U09's single compose) | P0 |
| P2 | U10–U18, U41–U48 | Server protocol (D3: before render), server perf fixtures and budgets, read-path optimisation, refresh admission | U00 |
| P3 | U19–U26 | Client protocol, outbox, store semantics, failure UX, release gate | P1, P2 |
| P4 | U27–U33 | Interaction, freeze, layout stability, Re-arrange | U26 (U27–U28 may start after P1) |
| P5 | U34–U35 | Render layering | U26 (D3), U28 |
| P6 | U36–U40 | Layout engine, adaptive slicing, acceleration, final acceptance | U30; U40 depends on all |
| P7 (rev 6) | U50–U54 | Ack-only apply, speculative client writes (anchors and trust), timeout notice, perf realism and D8 write re-measure, pinned persons outside the visible set | U13, U21, U23; U53 and U54 gate U26 |

P2 can run in parallel with P1, because it only touches the server.

---

## P0 Baseline

### U00 Journal, baseline, docs index
- Create the journal. Record the baseline:
  - CT `test/features/constellation test/features/graph`;
  - PT;
  - ST constellation tests;
  - LINT counts.
- Link the three docs from `docs/README.md` under plans.
- **Acceptance:** the journal records baseline pass counts. No code changes.

### U01 Instrumentation and benchmark fixture
- **Files:** `packages/client/lib/features/constellation/ui/util/constellation_perf.dart` (new); `test/features/constellation/fixtures/synthetic_field.dart` (new).
- `dart:developer` `Timeline` spans:
  - `constellation.drop→draggable`, `drop→acked`, `drop→reflowed`;
  - `layout.job`, `compose`, `scene.build`;
  - long-task detector: a frame-timing callback that logs any build or raster over 50 ms in debug and profile.
- A debug-only perf HUD toggle in the dev menu (no release cost).
- Synthetic field generator: N = 100/300/600 people and requests with anchors, a deterministic seed.
- Benchmark test (tagged `bench`, excluded by default) that measures compose, layout and a pump of drag frames, writing JSON to `build/bench/`.
- **Tests:** a generator determinism test.
- **Acceptance:** the baseline numbers for N = 100/300/600 are in the journal (I4 reference).

## P1 Purity and splits (no behaviour change)

### U02 Domain geometry, layout purity (ARCH §4.1, §8)
- **New:** `features/constellation/domain/layout/layout_geometry.dart`, containing records `LPoint = ({double x, double y})`, `LSize`, `LRect` plus helpers.
- Swap `dart:ui` `Offset`/`Size` in `domain/constellation_layout.dart` and `features/graph/domain/layout/radial_hop_positions.dart`.
- Add UI adapters (`ui/scene/geometry_adapters.dart`) at every call site in `ui/` and `features/graph/ui/utils/tentura_layout_algorithms.dart`.
- **Tests:** the existing `constellation_layout_test.dart`, `constellation_p06_composition_layout_test.dart` and graph layout tests are the oracle, unchanged except for type adaptation in their fixtures.
- **Acceptance:**
  - `rg "dart:ui|package:flutter" packages/client/lib/features/constellation/domain packages/client/lib/features/graph/domain/layout` is empty;
  - oracle tests pass;
  - LINT clean.

### U03 Composition purity (`NodeDetails` out of domain)
- `constellation_anchor_composition.dart` emits `LayoutNodeSpec` (a domain DTO in `layout_geometry.dart`) instead of importing `NodeDetails`. The scene side maps `LayoutNodeSpec` → `NodeDetails`.
- **Acceptance:** no `features/graph/domain/entity/node_details.dart` import under `constellation/domain`; the composition and layout oracle tests pass.

### U04 Infrastructure and account ports
- **New:** `lib/domain/port/{clock_port,op_id_port,wake_up_port}.dart`, with Injectable adapters in `lib/data/service/` and mocks.
- **New:** `features/constellation/domain/port/constellation_account_port.dart` plus an adapter over the existing account source, following `AttentionAccountPort` (`lib/domain/attention/attention_case.dart:52-70`).
- Run `build_runner`.
- **Tests:** the adapters' unit tests, and a fake clock / wake-up port for later domain tests (`test/support/`).
- **Acceptance:** DI resolves in the test env (CT of one DI smoke test).

### U05 Cubit orchestration fixes (ARCH §8)
- **New:** `ConstellationMemberWebsCase` (wraps the port). Add `ForwardCase.offerHelp` (delegating to the repository).
- `ConstellationCubit` stops injecting `ConstellationMemberWebsPort` and `ForwardRepository` (C:719, C:2268) and receives cases instead. Update the screen construction.
- **Tests:** existing cubit tests (adapted fakes); a new `ForwardCase.offerHelp` test.
- **Acceptance:** `rg "ForwardRepository|ConstellationMemberWebsPort" packages/client/lib/features/constellation/ui` is empty; LINT clean.

### U06 Freezed port DTOs
- Convert the client `ConstellationAnchorUpsertResult` and `ConstellationAnchorDeleteResult` (`domain/port/constellation_anchor_repository_port.dart:3,13`) to Freezed, and run codegen.
- **Acceptance:** CT constellation passes.

### U07 Extract `ConstellationSceneController`
- Move `GraphController` ownership, `_rebuildGraph`, layout hand-off (`_requestConstellationLayoutHandoff`, tickets, `_placementHandoffGraphIds`) and the geometry adapters from the cubit into `ui/scene/constellation_scene_controller.dart`. It is screen-owned and disposed with the screen.
- The cubit keeps its public API by delegating.
- **Tests:** all existing constellation tests unchanged (pure refactor). Add a controller-level test for hand-off release.
- **Acceptance:** no behaviour change, and CT constellation, graph and body pass with identical counts. The cubit shrinks by at least 800 lines.

### U08 Extract `ConstellationInteractionController`
- Move the drag-cluster state (`_draggingNodeId`, `_placementCluster*`, `_clusterStartCentres`, `_suppressLateGestureEnd`, `_placementSeq`, presentation token updates and cluster clamping) into `ui/scene/constellation_interaction_controller.dart`, behind the existing cubit methods.
- **Acceptance:** pure refactor; existing interaction and cubit tests pass.

### U09 `ConstellationFieldStoreCase` (read side split)
- **New:** the store case (ARCH §5.3), on the **current** protocol (FULL plus ANCHORS):
  - account generation via `ConstellationAccountPort`, independent of leases;
  - `lease()`, with visibility aggregated across leases and the browser;
  - single-flight refresh with the existing debounce and spacing policy;
  - catch-up issues **one** FULL;
  - no fetches while hidden (ANCHORS included);
  - params binding (`ConstellationProjectionParams`);
  - FULL read-sequence ordering, independent of anchor revision;
  - one emit per applied change.
- The read half of `ConstellationAnchorCase` and all of `ConstellationFieldCase` move here. The cubit composes **once**: FC's internal compose is removed.
- `preflightRequestAction` reads `current` instead of fetching FULL.
- **Tests:**
  - migrate `constellation_anchor_case_test.dart` (read parts) and `constellation_realtime_refresh_test.dart`;
  - new: logout with zero leases clears state; hidden → no ANCHORS fetch; catch-up → exactly one FULL; obsolete-params results are ignored.
- **Acceptance:**
  - FULL compose count per load = 1 (counter);
  - no regression in the constellation suite;
  - `ConstellationFieldCase` (client) deleted;
  - the write half remains in `ConstellationAnchorCase` until U21.

## P2 Server protocol

### U10 m0224: op log and target watermark
- `constellation_anchor_op_log(viewer_id uuid FK users ON DELETE CASCADE, client_op_id text, fingerprint text, result jsonb, revision bigint, created_at timestamptz, PRIMARY KEY (viewer_id, client_op_id))`.
- `constellation_anchor_target_watermark(viewer_id, target_kind, target_id, revision bigint, PRIMARY KEY (viewer_id, target_kind, target_id))`, which survives anchor deletion.
- Register both in `_migrations.dart`.
- **Size limits in the schema:** `client_op_id varchar(64)`; `fingerprint bytea CHECK (octet_length(fingerprint) = 32)`; `result` size-checked (≤ 256 bytes). No secondary indexes.
- **Tests (pg):** cascade on user delete; the watermark row survives anchor delete; oversize id, digest or result → constraint violation.
- **Acceptance:** the migration-upgrade test passes, and `drift_schemas` stays empty (raw migrant SQL).

### U11 `withMutatingRepeatableRead` (bounded, jittered retry)
- `TenturaDb.withMutatingRepeatableRead(userId, action)`:
  - `SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ WRITE` as the first statement;
  - mutating-user `set_config`;
  - zone context identical to `withMutatingUser` (`tentura_db.dart:180-207`);
  - wrapped in `postgres_serialization_retry.dart` for whole-transaction retry, extended with bounded jittered backoff (max 3 attempts) and an end-to-end deadline (env knob, default 2 s). The backoff sleep happens **after rollback, outside the DB connection** (the worker's only connection is free while waiting). The existing callers keep their behaviour.
- The deadline is only fully enforceable once U45's connector deadline ships. Until then, the MR portion is bounded by the env receive timeout, set to the interactive budget for constellation calls.
- **Metrics:** connection queue time, transaction age and retry count, via the U41 recorder.
- **Tests (pg):** isolation level asserted via `current_setting('transaction_isolation')`; a forced serialization failure retries with jitter; the deadline is respected; actor context is visible to triggers.

### U12 Anchor projection reader extraction
- Extract the anchor-projection half of `constellation_field_snapshot_reader.dart` into `data/repository/constellation_anchor_projection_reader.dart`. The ANCHORS read uses it. It must work inside an outer transaction (reusing the m0222 memo).
- **Tests:** existing snapshot and ANCHORS pg tests unchanged; a new equality test (extracted reader output == previous ANCHORS output on fixtures).

### U13 `applyBatch`: port, repository, server case
- Port `ConstellationAnchorRepositoryPort.applyBatch(viewerId, ops, params)` → `AnchorApplyBatchResult(beforeRevision, afterRevision, results, projection)`.
- The repository uses U11's transaction:
  - cursor `FOR UPDATE`;
  - per op in order: dedupe lookup (same fingerprint → recorded result, no write; different fingerprint → `REJECTED(op_id_reused)`) → authorization (existing `constellation_anchor_upsert_authorization.dart`) → `ifRevision` vs watermark (mismatch → `REJECTED(conflict)`) → write → watermark upsert → op-log insert;
  - then the projection via U12 at the final revision.
- **Performance shape (ARCH §4.4, §7.5–7.6):**
  - **prepare before lock:** compute visibility (one memoised computation per viewer and context), trust edges, profiles and pinned-beacon readability *before* `FOR UPDATE`, inside the same RR transaction;
  - after the lock, **batch-load** dedupe rows and watermarks (one query each);
  - person authorization uses the **shared memo** instead of a per-op `person_visible_peers_symmetric` (`constellation_anchor_upsert_authorization.dart:42`);
  - the op-log result is minimal (status, reason, resulting revision, position), with no projection;
  - prepared inputs cover existing anchors **plus the requested upsert targets**, the potential holder/support closure is computed from the prepared trust edges, and only the required profiles and beacon records are batch-fetched. After the writes, the final rows are re-read and the projection assembled;
  - **degraded MR** (m0222's fail-closed empty set) → the batch aborts with a retryable error, never an op-log rejection.
- **Contention gate:**
  - 2/4/8 concurrent tabs of one viewer, sustained writes, cold preparation and cascades;
  - record attempted vs completed transactions, exhausted retries and wasted preparation time;
  - if exhausted retries exceed 1% or wasted preparation exceeds 20% of DB time at 4 tabs, switch the repository to **lock-first** order (a single flag in the repository), re-run, and record both results in the journal.
- The server `ConstellationAnchorCase.apply` validates the envelope: ≤ 64 ops, no duplicate ids or targets, position required for UPSERT.
- **Tests (pg):**
  - replay → recorded result with no revision bump;
  - reused id with a different payload → reject;
  - `ifRevision` conflict;
  - mixed accept and reject in one batch;
  - forced DB error → full rollback;
  - the returned projection equals a fresh ANCHORS read at `afterRevision`;
  - a concurrent foreign write → serialization retry, with the projection including it;
  - concurrent visibility change and cascade delete;
  - **MR RPC count** for a 64-op person batch = 1 + U per context, counting actual connector RPCs (instrument the connector shim, not just symmetric-function evaluations), with trust churn committed concurrently from a second connection (requires U46);
  - first-pin, filter-hidden pin, mixed rejection and foreign-write-retry fixtures;
  - an MR outage during a batch → retryable error, no op-log row;
  - **perf (U41 fixtures, tag `perf`):** 1-op and 64-op apply p50/p95 plus cursor-hold p95 recorded against the ARCH §7.6 targets; EXPLAIN (ANALYZE, BUFFERS, WAL) saved for the mutation queries; WAL/op and tuple bytes per op-log row recorded.
- **Acceptance:** the server domain imports ports only (`rg "package:tentura_server/data/repository" packages/server/lib/domain` is empty).
- **Rev 6:** the projection, prepare-before-lock, visibility authorization, MR RPC count gate and degraded-MR abort are **superseded by U50** (ARCH §4.4, §7.1 rev 10). The landed parts that stay: RR transaction, cursor lock, dedupe, watermarks, `ifRevision`, op log, batched flush, envelope validation, lock-first order.

### U14 GraphQL `constellationAnchorsApply`
- Input types `input_field_constellation_anchor_op.dart` (the `InputField*` list pattern; no `.nonNullable()` on list types), output types in `custom_types.dart`, mapper in `constellation_gql_maps.dart`, mutation registered in `_mutations_all.dart`.
- Projection params come as arguments (ARCH §7.1). **Rev 6:** U50 removes them and the projection from the schema.
- The **old upsert/delete stay** until U26.
- **Tests:** a GraphQL controller test for argument parsing, null-safety and error mapping.

### U15 m0225: canonical deferred anchor notifications
- Replace the anchor row trigger and add a cursor trigger as `DEFERRABLE INITIALLY DEFERRED` constraint triggers calling the strict publisher with the canonical envelope: event `update`; id and recipient = viewer; `revision` = the final cursor revision as a decimal string. Skip when the viewer row is gone.
- Remove the Dart absent-delete notify (`constellation_anchor_repository.dart:356-384`).
- Each deferred callback checks a transaction-local publication marker keyed by `(viewer, final revision)` (`set_config(..., true)`) and calls the publisher only once per viewer per transaction.
- **Tests (pg):** one delivered hint per committed batch (mixed ops, absent delete, cascade); rollback → none; payload revision equals the committed cursor revision; a 64-op batch makes exactly **1** publisher call (counter); commit latency with and without triggers recorded (perf tag). Concurrent notifying commits record transaction-body and COMMIT latency separately; slow-listener backlog is measured.

### U16 Fan-out per-kind extras
- `websocket_path_entity_changes.dart`: refactor `_forwardedExtrasByKind` validation per kind (today it assumes seen timestamps, `:35-46`). Forward `revision` for `constellation_anchor`, and support the `constellation_field` kind.
- **Tests:** fan-out unit tests for each kind; a malformed revision is dropped with a warning.

### U17 m0226: field-hint producers
- Trust changes and MR publication (the global epoch, `m0202.dart:39`) → **one global marker** NOTIFY (no per-viewer enumeration). The fan-out side coalescing and broadcast is U43.
- Block changes → both parties.
- **Tests (pg plus fan-out):** a trust change alters a third viewer's field and that viewer receives a hint (via U43 once landed; until then, the marker is asserted at the NOTIFY level); block → both parties; 100 trust changes in one second → 100 markers but ≤ 1 broadcast per window (with U43).

### U18 Lean constellation profile lookup
- `UserProfileBatchLookup.constellationProfilesByIds`: one query for name, handle and image. Used by the field and projection readers.
- **Tests (pg):** parity of the returned fields with the 4-query path, and query count = 1; perf: FULL and ANCHORS p50/p95 before and after recorded in the journal.

## P3 Client protocol, outbox, store semantics

### U19 Client wire layer
- Refresh the client schema from the server (documented script), add `data/gql/constellation_anchors_apply.graphql`, and run Ferry codegen.
- Add `ConstellationAnchorsApply` to `_tenturaDirectOperationNames` (`build_client.dart:265`).
- `ConstellationAnchorRepository.apply(ops, params)` → `ConstellationAnchorApplyResult` (Freezed) via a mapper.
- Realtime decode: `RealtimeEntityKind.constellationField`, and `RealtimeEntityChange.revision` (`BigInt?`) from WS extras.
- Mocks updated.
- **Tests:** mapper tests; the realtime decode test (revision kept, malformed ignored); repository test with a mocked client.

### U20 Outbox entities and desired-state overlay
- **New:** `domain/entity/placement_outbox.dart` (`PlacementOp`, `PlacementSlot`, `PlacementTargetState`, `PlacementOutboxState`; Freezed) and `domain/placement_overlay.dart` (`desiredAnchorProjection` plus the `unsaved` side map).
- **Tests (pure):**
  - the overlay applies upserts and deletes;
  - `latestPending` beats in-flight;
  - the unsaved map covers rejected, exhausted unknown, and in-flight over 1 s (fake clock).

### U21 `ConstellationPlacementCase`: R1–R4, R8, batching
- **New:** the case (ARCH §5.1). It replaces the write half of `ConstellationAnchorCase`, which is then **deleted**.
  - `place`, `unpin`; slots; flush loop (one in flight); batches cut at cluster boundaries (cap 64; the drag-cluster policy enforces ≤ 64);
  - settlement by `clientOpId`, published atomically through `store.settle`;
  - `commitUnknown` with backoff via `WakeUpPort` (same ids, 3 attempts), with a **jittered** retry on catch-up or reconnect, prioritised over recovery reads;
  - promotion rules; account generation capture and stale-drop.
- **Tests:**
  - R1: A→B on the same target with A ok / rejected / timeout;
  - R2: over 64 ops, clusters never split;
  - R4: same ids on retry;
  - promotion: an exhausted unknown blocks only its target;
  - R8: logout mid-flight → no further requests;
  - I5: `place` → exactly one apply and zero ANCHORS fetches.
- **Rev 6:** settlement consumes the minimal ack (U51); the D14 overdue event is added by U51.

### U22 Retry, Discard, compensation (R7)
- Retry of a rejection uses a new id; retry of unknown keeps the id.
- Discard on queued or rejected drops the slot. On unknown it replays, then compensates (`ifRevision` = `resultingTargetRevision`, baseline `preOpConfirmed` captured before first dispatch) or drops. On in-flight it uses `discardOnSettle`.
- Unsent compensation can be cancelled by newer intent; dispatched compensation settles before its successor.
- **Tests:** every branch above with a fake repository, plus the conflict reject → dropped.

### U23 Store coverage, echo suppression, field hints
- `coveredRevision`: a complete projection at ≥ covered replaces anchors (from a read). **Rev 6:** an ack no longer carries a projection; it merges rows and advances coverage only when `beforeRevision == coveredRevision` (U51, ARCH §5.3).
- Echo ≤ covered → ignored. An uncovered hint (including +1) → one coalesced ANCHORS resync. Hints buffered while a request is in flight are evaluated after settlement.
- `constellation_field` hints are non-urgent and **lazy (D8)**: they mark the field stale, refresh at most once per D8 window while visible, and refresh immediately on tab return or opening Constellation. They always request FULL.
- **Refresh scheduling (ARCH §5.3):**
  - one pending refresh plus an immutable retry-not-before deadline per params;
  - `RETRY_LATER` honoured and never shortened by hints, resume or catch-up;
  - an in-flight FULL satisfies coalesced triggers unless a newer invalidation arrived;
  - visibility is re-checked at dispatch.
- **Tests:**
  - F5 in both orders (rev 6 semantics, U51); echo suppression; +1 resync; buffered hint;
  - global hints are lazy: 50 hints while visible → ≤ 1 FULL per window; hidden → 0; tab return → 1;
  - a field hint is never suppressed by coverage;
  - `RETRY_LATER` with repeated hints never fires early;
  - reconnect plus resume plus repeated rejection together → bounded FULL count.

### U24 Cubit and scene wiring to desired state; remove the I/O gate
- The cubit and scene controller consume `store.changes` + `placement.changes` → `desiredAnchorProjection` → memoised compose → scene.
- Remove `placementActionsEnabled` (state field, getter and all gates), `deferredRefreshTargets`, `_placementBusy`, `_outstandingWrites`, `_placementSeq` and the interim hacks from `67ee9fa53`.
- `canDragNode` = kind and ownership only (I1).
- **Tests:**
  - widget: drag B while A's apply is pending → B drags and the camera doesn't move;
  - the ack causes no relayout (counter);
  - port the interim `67ee9fa53` tests to the new model.
- **Rev 6:** the ack no longer delivers pinned records or support data. The scene must draw a new pin from the record captured at grab time, with no support fetch (D12, U51); "the ack causes no relayout" now also covers a pin of a composer-only person.
- **Acceptance:** `rg "placementActionsEnabled|hasPendingWrite" packages/client/lib` is empty.

### U25 Failure UX: placement marker (D1)
- `ui/widget/constellation_placement_marker.dart`: a "Not saved — server problem" badge plus a menu with **Retry** and **Discard my move**, and a "Saving…" cue for in-flight over 1 s. Design-system tokens only.
- l10n keys in all arb files, en and ru: `constellationPlacementNotSaved`, `constellationPlacementRetry`, `constellationPlacementDiscard`, `constellationPlacementSaving`.
- Gesture affordances per the cross-platform rule: secondary-tap and hover toolbar, never long-press only.
- **Tests (widget, structural):** the marker appears on rejected and on exhausted unknown; Retry and Discard call the case; Discard animates to confirmed.
- **Skill:** `material-3-flutter`.
- **Rev 6:** the rejection reason for a missing target is `target_not_found` (was `target_unavailable`); the marker copy is unchanged. The D14 notice is a separate snackbar (U51), not part of the marker.

### U26 Release gate: protocol switch
- **Server:** remove `constellationAnchorUpsert` / `constellationAnchorDelete` and their port and repository paths; raise `kDefaultMinClientVersion`.
- **Client:**
  - remove the old upsert/delete gql, repository methods and routing entries (`build_client.dart:267-268`);
  - bump `pubspec.yaml` semver plus `web/index.html` `flutter_bootstrap.js?v=` (run the app once and check `git status`).
- Web e2e (`scripts/run_client_integration_web_local.sh`, unwrapped per AGENTS.md):
  - drag A, then immediately drag B → both persisted, no camera pan; **rev 6:** exactly one apply per drop and **zero** ANCHORS/FULL requests after it (network log), and A and B stay where dropped across a reload;
  - kill the network during a drop → the node stays put, the D14 notice appears after 15 s, the marker after exhausted retries; restore → Retry persists;
  - **rev 6:** toggle trust on a person from the Constellation person context → the toggle flips at once with no loading state, one trust write and no profile or field read follows.
- **Preconditions:** the owner confirms D8 in the journal. U45's verified connector build is deployed in the target environment. **Rev 6:** U50–U53 have landed.
- **Server perf gate:** U41's fixtures run against ARCH §7.6. Any p95 over target → blocked with evidence (no release). **Rev 6:** the write rows are measured on the U50 ack-only write, with the U53 fixture realism, and the D8 write p95 comes from U53. A load test of publication burst, reconnect burst and concurrent tabs at the **D8 declared population** sustains the D8 staleness bound and write p95 with ≥ 30% headroom, including completed refresh throughput and maximum staleness, not just a bounded queue.
- **Acceptance:** full client CT, ST (with pg), LINT for both packages, e2e green, server perf gate green. The journal records the version numbers.

## P4 Interaction, freeze, stability

### U27 Graph package: pointer and camera arbitration (ARCH §5.4, §5.7.1)
- Extend the selective recognizer (`node_drag_gesture.dart:516`) to an owner recognizer for mouse, touch and stylus, replacing the raw `Listener` capture path.
- Camera arbitration by source:
  - gesture-origin pan/scale blocked during node ownership, plus additional touches;
  - wheel and trackpad allowed through a camera API that re-projects the grab point;
  - programmatic updates.
- Drag survives resize (`controller.dart:915-922`).
- **Tests (PT):** node tap; canvas pinch; node-origin extra touch ignored; wheel during drag; zero gesture-origin camera displacement; resize mid-drag continues.

### U28 Graph package: transitions, publication guards, scene revision
- Non-destructive `pauseTransitions()` / `resumeTransitions()` that keep destinations (do not reuse `controller.dart:731`).
- `animateTo(targets, {skip})` with a > 2 px threshold from current positions; remove the global 350 ms tween.
- Every queued publication callback checks generation, ticket and freeze (`controller.dart:611`).
- `sceneRevision` getter; stable layout-algorithm identity by revision (no re-request on rebuild).
- **Client:** the tap resolver compares `sceneRevision` (fixes `constellation_body.dart:779-783`).
- **Tests (PT plus CT):** freeze between acceptance and callback → no publication; resume keeps destinations; label tap works (resolver live); rebuild doesn't re-request layout.

### U29 Freeze gate and interaction state machine (D5, I2)
- `ui/scene/scene_update_gate.dart`. The interaction controller implements the ARCH §5.4 machine:
  - on entering `dragging`: freeze, pause transitions, invalidate jobs and tickets;
  - inputs coalesce while frozen;
  - release exactly once on drop, cancel, lost capture or tab hidden;
  - drop → one combined compose and layout rebased on frozen displayed geometry and one transition;
  - cancel → no op, cluster animates back;
  - unchanged inputs → resume.
- **Tests (widget):**
  - store, outbox and transition activity during a drag → zero committed movement;
  - release → exactly one compose, one layout and one transition;
  - each release path fires once;
  - tab hidden mid-drag = cancel;
  - visibility revoked mid-drag is applied on release.
- **Rev 6:** an ack arriving mid-drag is coalesced like any store input and changes nothing visible on release (it changes confirmed, not desired). The D14 snackbar is chrome: it may appear mid-drag, and the test asserts zero committed movement and an uninterrupted drag (U51).

### U30 Layout stability contract (I3)
- The layout input includes the previous result. Free nodes with unchanged inputs and no new overlap are hard-kept. Changed or overlapped nodes get a minimum-displacement search from the old spot. New nodes go into free space. Nodes with unresolved intent are fixed.
- No layout on selection, highlight or label budget (`selectRequest`/`selectPerson` and label-budget paths stop calling `_rebuildGraph` layout).
- **Tests:**
  - a domain property test (seeded random diffs not touching X → X unchanged; 200 cases);
  - a widget test: selection tap → zero layout runs.

### U31 Re-arrange action (D2)
- `constellation_camera_controls.dart`: the action is visible iff `hasUserPlacements`. It triggers a full plan with a stable seed; anchored and pending nodes stay fixed; there is no server write.
- l10n `constellationRearrange`. Skill: `material-3-flutter`.
- **Tests:** hidden before the first move and shown after; invoking it leaves anchors unchanged and moves only free nodes; the seed is deterministic.

### U32 Composer loop fix
- The screen's composer `BlocListener` gets a `listenWhen` (no `enterComposing` per pointer move).
- Composer people positions go through interaction-controller listenables, not recompose.
- The 4 s candidate poll is replaced by refresh on composer open plus a field hint.
- **Tests:** a composer drag of N moves → 0 recomposes; existing composer tests pass.

### U33 Id-map fixes
- `GraphController._replaceNodeAndEdgeSets` (`controller.dart:278-309`) and the cubit/scene `_profileFromPeer` use id maps instead of linear scans.
- **Tests:** PT topology tests; the U01 benchmark shows reconcile time at N = 600 (journal).

## P5 Render layering (after U26, per D3)

### U34 Per-node position listenables
- The package exposes stable, disposed-per-node `ValueListenable<Offset>`. Node widgets subscribe individually. Structural membership rebuilds separately. Coherent geometry and presentation revisions feed paint and hit test.
- The body's `BlocBuilder` stops depending on `graphRevision`.
- **Tests (PT plus CT):** a drag move rebuilds only the dragged nodes (build counter); listeners are disposed when a node is removed; hit testing is consistent with paint.
- **Acceptance:** the U01 benchmark drag frame at N = 300 is under 8 ms UI-thread time (profile web, journal).

### U35 Labels and edges
- Overlay label placement cached per (layout revision, zoom bucket), with a grid-indexed `occupied` set; pan is a translate.
- The edge painter gets a real `shouldRepaint` (revision), reuses `Paint`, and moves camera scale into the canvas transform.
- **Measure.** Only if edges exceed 2 ms per frame at N = 300: a cached `Picture` excluding live edges (dragged and animating endpoints), invalidated by geometry revision and style, with old pictures disposed.
- **Tests:** a pan frame does no label placement (counter); the painter doesn't repaint without a revision change.
- **Acceptance:** pan frame under 8 ms at N = 300 (journal).

## P6 Layout engine, slicing, acceleration

### U36 Spatial index benchmark (D6)
- `domain/layout/spatial_index.dart`: the interface, `BruteForceIndex`, plus benchmark-only sweep-and-prune, uniform grid and dynamic AABB tree under `test/bench/`.
- Benchmark at N = 100/300/600/1000 with realistic footprints and K ≈ 66: full, incremental (1–10 changed), and build plus invalidate.
- **Deliverable:** a decision record in the journal (table plus choice).
- **Rule:** keep brute force unless another implementation wins full or incremental by at least 30% at N = 300 *including* maintenance cost.

### U37 Resumable `LayoutJob`
- `ConstellationLayoutEngine.start(previous, next)` → `LayoutJob.step(units)`. Planning, dependency diffing, obstacle preparation and placement are phases. Units are bounded (candidate evaluation and obstacle-scan chunks), measured worst case ≤ 0.5 ms at N = 1000.
- **Oracle:** for full plans, the job result equals today's `computeConstellationPlacedLayout` output on all existing layout fixtures, or the documented deterministic difference is approved in the journal.
- **Tests:** step-by-step equals one-shot; cancel mid-job leaves no partial publication.

### U38 Adaptive slicing (D7)
- **Pure:** `lib/domain/scheduling/adaptive_slice_controller.dart`. EWMA α = 0.3, first batch `setpoint / ewma`, +8 units on time, ×0.5 over, floor 1, hard cap 8 ms.
- **UI:** `lib/ui/utils/frame_slice_scheduler.dart`:
  - a frame permit (one slice per frame);
  - a deadline check after each unit;
  - `scheduleTask(Priority.idle)`, with a 100 ms starvation wake-up via `WakeUpPort` → `Priority.animation`;
  - a job token against duplicates; pause on pointer down; cancel on a newer job.
- Wire the scene controller layout through it, and the label placement if U35 shows it is needed.
- **Tests:** controller convergence with a step change in unit cost; the scheduler under continuous animation still progresses; never two slices per frame; a stalled frame wakes up.

### U39 Adopt the benchmark winner (conditional)
- Only if U36 chose a non-brute-force index: implement it in `domain/layout/`, using `BruteForceIndex` as the test oracle (randomised equivalence over 1,000 cases).
- Otherwise, record "brute force retained" and close.

### U40 Final acceptance
- **Server:** re-run the U41 suite; record the final p50/p95, MR RPCs per op (**0 for apply since rev 6**), WAL/op, op-log growth per 1k ops, aggregate FULL rate under the publication burst, listener → WS latency, and the D8 write p95 on the ack-only write (U53).
- **Profile web benchmark** at N = 100/300/600, recorded in the journal. I4: drag frame and pan frame under 8 ms each; no task over 50 ms across drop → ack → reflow.
- **Web e2e:** the full drag, refresh-mid-drag, failure, Re-arrange and composer flows.
- Full CT, PT, ST (with pg) and LINT for both packages.
- **Docs:** update `docs/features/` constellation docs and the architecture doc status (→ implemented). Close #235 with a summary comment (ask the owner before posting).

## P2 additions: server performance (ARCH §7.3, §7.5, §7.6)

### U41 Server perf fixtures, recorder and budgets
- **Fixtures** `packages/server/test/perf/` (tag `perf`, excluded by default; MR suites serialised):
  - V = 100/300/1000 with sparse and dense trust;
  - reciprocal and fallback-score populations;
  - C = 100/1k/10k discoverable candidates;
  - A = 0/20/200 anchors;
  - batches of 1/16/64.
  Built on `test/support/disposable_pg_target.dart`, with lock probes scoped to the disposable DB.
- **Recorder:** p50/p95, query count, MR RPC count, cursor wait and hold, connection queue time, tx age, retry count, WAL bytes (`pg_current_wal_lsn` delta), EXPLAIN (ANALYZE, BUFFERS, WAL) capture. Output JSON goes to `build/perf/`.
- **Baseline run** for today's FULL, ANCHORS, upsert and delete, cold and warm, with real MR latency. Calibrate the ARCH §7.6 targets and record the calibrated budgets in the journal.
- **Prepared datasets (local, 2026-10-06):**
  - `tentura_devcopy` (dev snapshot, V ≤ 81);
  - `tentura_perfsynth` (V ≈ 1,000, C ≈ 10k);
  - scripts in `scripts/perf/`: `constellation_synth.sql`, `constellation_sql_bench.sql`, `constellation_gql_bench.py`, `run_server_db.sh`.
  MR holds one graph at a time, so reload it for the DB under test and restore the `postgres` graph afterwards.
- **Starting point:** `issue-235-constellation-interactive-measurements.md`, run 1. It gives local per-unit costs and one-worker saturation, but the local graph is too small (V ≤ 6, C ≤ 30). U41 must therefore:
  - build dense synthetic fixtures (or a denser `scripts/seed_society` run);
  - take the real-data baseline on **dev**, which has `pg_stat_statements` and `auto_explain` (via the owner; no agent SSH);
  - check `mr_edgelist()` is non-empty before any MR-dependent run (a recreated MR container starts empty until `meritrank_init()`, normally run at server startup).
- **Measurement rules (ARCH §7.6):**
  - latency from admission through response encoding, failed attempts included; execution reported separately;
  - actual connector RPC counts;
  - WAL attributed on a quiet cluster, or labelled as cluster totals;
  - U = 0/10/100/1000 fallback populations, aged logs, rejection ratios, multi-worker tabs, trust churn, failure injection;
  - enough repetitions for p95 with uncertainty;
  - EXPLAIN JSON kept, mutating EXPLAIN rolled back;
  - `pg` and `mr` fixtures serialised separately through the wrapper.
- **Acceptance:** the suite runs through the wrapper and writes JSON for every fixture; the journal contains baseline numbers and calibrated, frozen budgets.
- **Rev 6:** the trust fixtures mirror edges into `user_trust_edge` only after the timed attempts (`test/perf/perf_fixture_matrix.dart:344-370`); U53 moves the mirroring before timing.

### U42 Discoverable candidates: partial index plus keyset scan (#233)
- A new migration (next free number after U17's), adding a partial index on `(user_id, id)` matching the kind, publication, discoverability and lifecycle predicates. Benchmark it against `m0193.dart:6567`.
- Rewrite the discoverable read (`constellation_field_snapshot_reader.dart:690-735`) per the ARCH §7.5 keyset contract:
  - `(user_id, id) > last_examined_key` under one RR snapshot, advancing over every examined candidate;
  - explicitly ordered batches; cap + 1 eligible rows; bounded overfetch;
  - exclusions and participation filters preserved;
  - the partial-index predicate implied by every query variant. Reconcile `constellation_field_repository.dart:207-214` with `constellation_field_selection.dart:100-109`.
- **Tests (pg):**
  - output parity with the current query (same ids, order, cap behaviour);
  - rejection runs crossing batch boundaries; an all-rejected population; filters, exclusions and the cap boundary;
  - a rejected candidate is never returned.
- **Perf gate:** the candidate-query gain on eligible fixtures (rows examined and readability calls reduced at least 5× at C = 10k with ≥ 10% readable), plus a whole-FULL regression limit (p95 not worse than baseline + 5% on any fixture). EXPLAIN evidence in the journal.

### U43 FULL refresh admission, server single-flight, coalesced broadcast
- **Fan-out:** the global `constellation_field` marker → a per-process **dirty generation**. At most one broadcast per coalescing window (env, default 30 s), sent in batches that yield to the event loop.
- **Worker-wide constellation DB scheduler** (`data/service/constellation_db_scheduler.dart` behind `ConstellationDbAdmissionPort`):
  - every apply, ANCHORS and FULL transaction is admitted before entering Drift, and no refresh transaction is queued inside Drift;
  - interactive writes take priority, with a reserved refresh share (env, default 30%) and oldest-first fairness;
  - queue deadlines cover all waiting;
  - over the limit → typed `RETRY_LATER` with a backoff hint, honoured by the client store (U23).
- **Per-(viewer, params) single-flight** (isolate-scoped, in the server `ConstellationFieldCase`), applied **before** admission so followers don't consume permits. A read started at generation g acknowledges g only.
- **Tests:**
  - 100 markers in one window → 1 broadcast;
  - admission over the limit → `RETRY_LATER`;
  - two same-viewer FULLs on one isolate → one DB computation; across 2 isolates → ≤ 2;
  - a marker during a read keeps the generation dirty;
  - write p95 during a publication storm stays within the §7.6 budget;
  - refresh maximum age during sustained writes stays within D8. **Load (perf):** a publication burst with 1k simulated sessions; the journal records the FULL rate, queue age and maximum staleness.

### U44 Tx-local reuse and trust-edge query evidence
- Pinned-beacon readability is computed once per transaction and reused by hydration (`:247`, `:639`).
- Profiles are fetched once per transaction across the FULL and projection parts.
- For trust edges over the visible set (`:370`), capture EXPLAIN on dense V = 1000. Add or adjust indexes only with EXPLAIN evidence. No truncation of visibility, anchors or support paths.
- **Tests (pg):** `beacon_can_read_content` call count per pinned beacon = 1; snapshot parity on fixtures. **Perf:** ANCHORS p95 recorded vs baseline.

### U45 MR call budget on pgmer2 0.9.x
- **Done (2026-10-06):**
  - The connector deadline (pgmer2 0.8.3, upstream #89) ships in `postgres-tentura:v0.9.1` together with the 0.8.x→0.9.x upgrade path (upstream #92).
  - Compose and CI pin `meritrank-service:v0.12.0` + `postgres-tentura:v0.9.1` (`8b5aad7ff`), deployed to dev.
  - `ALTER EXTENSION pgmer2 UPDATE` → 0.9.1 verified locally and on dev.
- **Remaining (Tentura side):**
  - `MERITRANK_RECV_TIMEOUT_MSEC` is the whole-call budget (still 60000). Choose a per-call value above the measured **cold** MR cost on 0.12 (missing peers are sampled on demand), measured on `tentura_perfsynth`.
  - Constellation transactions set `SET LOCAL statement_timeout` to the request budget (U11/U13); the connector honours it while waiting.
  - Degraded vs empty visibility (U13).
- **Tests (Tentura pg/mr):** an MR blackhole during apply → retryable error within the budget + 100 ms, with the connection reusable after rollback. `mr_rpc_attempts()` deltas feed the U13 RPC-count gate.

### U46 Frozen RR visibility memo
- A new migration (next free number): `person_visible_peer_ids_tx` honours a tx-local `tentura_visibility.frozen` flag. Once set, after the first computation the memo ignores later stamp changes (`m0222.dart:104-119`). Constellation read and apply transactions set it. Trust-mutating transactions never do. **Rev 6:** apply no longer computes visibility (U50), so only read transactions need it.
- **Tests (pg):** a second connection commits trust changes continuously while FULL or apply runs → exactly one computation per (viewer, context) per successful attempt; a trust-mutating tx still invalidates; the failure-empty path is unchanged (fail closed).

### U47 MR walks cache + snapshots (MeritRank 0.12)
- **History.** On MeritRank 0.11.1 a walks cache below one read's working set made every `mr_mutual_scores` recalculate peer frames (≈ 6 s at V ≈ 1,000, run 4); 1200 fixed it (`75051dd09`).
- **Done (2026-10-06).** Switched to MeritRank 0.12.0, which serves absent peers from reverse-score snapshots (D14), so the cache only has to hold the active readers. Compose and CI set `MERITRANK_WALKS_CACHE_SIZE=300` (≥ active readers, 202 now, plus headroom; never lower), `MERITRANK_ON_DEMAND_NUM_WALKS=10000` and `MERITRANK_SNAPSHOT_STALENESS=2` (`8b5aad7ff`). Deployed to dev: MR uses 542 MiB.
- **Remaining:**
  - document the memory budget (≈ 1 MB per frame at 10k walks, plus `MERITRANK_SNAPSHOTS_MB`, default 256) and the "cache ≥ active readers" rule in `docs/production-deploy.md`;
  - surface MR over-capacity / snapshot pressure in the server's MR health signal.
- **Acceptance:** on `tentura_perfsynth` with these settings, warm `mr_mutual_scores` p95 ≤ 100 ms for the heavy viewer (V ≈ 1,000), and FULL p95 within the ARCH §7.6 budget, including with 1 write per 100 reads. The journal records cold and warm latency and MR memory.

### U48 Cross-request visible-set cache (ARCH §7.4a), OPTIONAL
- Build this only if the **cold** first-read cost (about 2–2.4 s at V ≈ 1,000 after an MR restart or a walk-dirtying write) proves to matter after U47. It is not a release precondition.
- A migration adds a transactional `trust_generation` counter, bumped in-tx by every trust, block or relationship change affecting visibility, plus the `person_visible_set_cache` table.
- `person_visible_peer_ids_tx` consults and fills the cache under the request snapshot (key: viewer, ctx, MR epoch, trust generation). Degraded results are never cached.
- **Tests (pg):**
  - concurrent uncommitted trust change → no stale hit after commit;
  - rollback → no bump;
  - block both directions;
  - MR epoch bump → miss;
  - MR failure → no row;
  - parity with uncached visibility.
- **Perf:** on `tentura_perfsynth` a warm FULL p95 ≤ the ARCH §7.6 budget, with exactly 0 MR RPCs on a warm hit (`mr_rpc_attempts()` delta).

## Rev 6 additions: speculative lazy writes (ARCH rev 10, D9–D14)

**Summary of amended units.** U13 (projection, visibility and MR parts superseded by U50), U14 (args), U21 (ack settlement), U23 (coverage from the ack), U24 (no ack-delivered pinned records), U25 (reason code), U26 (e2e wording, perf gate source, preconditions), U29 (ack and snackbar during a drag), U40 (acceptance numbers), U41 (fixture realism), U46 (reads only). Units that already landed are not reopened; U50–U54 carry the changes.

### U50 Server ack-only apply without visibility authorization (ARCH §4.4, §7.1 rev 10; D10, D11)
- `ConstellationAnchorRepository.applyBatch` (`data/repository/constellation_anchor_repository.dart:81-226`):
  - remove `_prepareBatchVisibility` (`:90`, `:232-285`), `reader.prepare` (`:95`) and `reader.readPrepared` (`:212`) from the write path;
  - keep lock-first (batch lock, cursor `FOR UPDATE`), the batched dedupe and watermark lookups (`:105-157`), the per-op decision loop and the single flush (`:211`);
  - add one batched existence query for the upsert targets (`user` / `beacon` ids, matching the FKs at `m0193.dart:7752-7763`) → per-op `REJECTED(target_not_found)`;
  - drop the `authorized` branch of `_batchOpRejection` (`:347-349`) and the `target_unavailable` reason;
  - return `AnchorApplyBatchResult(beforeRevision, afterRevision, results)` with no projection; each OK upsert result carries the stored row (position, revision, `placedAt`), and each result a `replayed` flag (true for a recorded result, `:168-177`).
- Remove the prepare-first path and its flag (`lockFirst` / `lockFirstOrder`, `:34-67`, `:89`); the contention gate's "wasted preparation" metric is retired.
- Port, server case and GraphQL: `AnchorApplyBatchResult` loses `projection`; `ConstellationAnchorsApplyResult` loses `anchorProjection`; the mutation loses `context`, `showClosed`, `participatedOnly`; `ConstellationAnchorOpResult` gains `replayed: Boolean!` and returns the stored `anchor`.
- The op log is unchanged (minimal result, R9); `replayed` is derived, never stored.
- **Tests first (pg):**
  - the response has no projection fields (GraphQL controller test) and the mutation rejects the removed arguments;
  - a pin on a person who is not visible to the viewer → OK, stored (what reads show is U54); a blocked person → OK, stored;
  - a missing person or Request id → `target_not_found` for that op; the other ops in the batch commit;
  - a target deleted by a concurrent transaction after the snapshot → whole-tx retry → `target_not_found`, no FK error escapes;
  - replay → recorded result with `replayed: true`, no revision bump; reused id with a different payload → `op_id_reused`;
  - MR stopped (or a blackholed MR URL) → apply still succeeds within budget; `mr_rpc_attempts()` delta per apply = 0;
  - the U13 cases that remain valid (mixed accept/reject, `ifRevision` conflict, DB error → full rollback, one deferred hint per batch) still pass.
- Remove or rewrite the U13 tests that assert projection equality, visibility rejection, MR RPC = 1 + U and degraded-MR abort; record each removed test in the journal with the rev 10 reason. This is a contract change, not a weakened test.
- **Acceptance:** ST constellation (with pg) green; LINT clean; `rg "readPrepared|_prepareBatchVisibility" packages/server/lib/data/repository/constellation_anchor_repository.dart` is empty; the U41 `apply_batch_b1` / `apply_batch_b64` fixtures re-run and recorded.
- **Depends:** U13, U14, U15. Ships in the U26 release with U51 (wire change; no legacy client, `kDefaultMinClientVersion` raised once).

### U51 Client speculative anchor confirmation, no support fetch, timeout notice (ARCH §5.1–5.3, §5.9; D10, D12, D14)
- Wire: refresh the schema, update `constellation_anchors_apply.graphql` to select only the ack fields, drop the params from `ConstellationAnchorRepository.apply`; mapper for `replayed` and the stored anchor row.
- Port DTO: `ConstellationAnchorApplyResult` (`domain/port/constellation_anchor_repository_port.dart:36-44`) loses `anchorProjection`; `ConstellationAnchorOpResult` (`:26-33`) gains `anchor` and `replayed`.
- `ConstellationPlacementCase.place` captures the grabbed node's record (field or composer snapshot) on the slot; it is never sent.
- Store: replace `settle`'s `_applyAnchors(result.anchorProjection)` (`constellation_field_store_case.dart:135-143`, called from `constellation_placement_case.dart:308`) with the ARCH §5.3 ack merge: settle slots; merge executed OK rows plus captured records; skip `replayed`; advance `coveredRevision` to `afterRevision` only when `beforeRevision == coveredRevision`; merge nothing for obsolete params. No fetch of any kind.
- `kLazyWriteAckTimeout = Duration(seconds: 15)` (ARCH §5.9) next to `kLazyFieldRefreshInterval` (`constellation_field_store_case.dart:26`). The placement case emits one `LazyWriteNotice` per overdue episode, measured from each op's first dispatch via `ClockPort` / `WakeUpPort`.
- UI: `lib/ui/widget/lazy_write_timeout_notice.dart` shows the design-system snackbar; l10n `lazyWriteAckOverdue` (en, ru); the Constellation screen subscribes. Skill: `material-3-flutter`.
- **Tests first:**
  - domain: ack with `before == covered` → coverage = after, echo ignored, zero ANCHORS/FULL; ack with a gap → rows merged, coverage unchanged, echo → exactly one ANCHORS resync; replayed OK → settled, not merged; obsolete params → settled, nothing merged; DELETE ack removes the row and its pinned record;
  - domain: pin of a field person and of a composer-only person → the record is in confirmed after settlement, and no support peers/edges are requested (fake repository counts zero reads);
  - domain (fake clock): no ack at 14.9 s → no notice; at 15 s → one notice; three overdue ops in one burst → one notice; a retry does not restart the timer; an ack at 10 s → no notice;
  - widget: the notice appears during a drag with zero committed node movement and the drag continuing (extends U29);
  - F5 in both orders with no lost row (rewrites the U23 F5 tests).
- **Acceptance:** CT constellation green; `rg "anchorProjection" packages/client/lib/features/constellation/domain/port` is empty; LINT clean.
- **Depends:** U50 (wire), U21, U23, U24, U25.

### U52 Speculative trust change through the graph, timeout notice (ARCH §5.8, §5.9; D13, D14)
- New `features/graph/domain/use_case/graph_trust_write_case.dart` (`@singleton`, `UseCaseBase`, account-scoped via the account port, memory only): one latest-wins slot per peer; one request in flight per peer; R4 retry schedule (same absolute amount, which is idempotent); `LazyWriteNotice` after `kLazyWriteAckTimeout`; generation reset on account change.
- The write calls the like repository's `setLike` (as `profile_view_case.dart:117` does) **without** the `fetchById` re-read (`:118`). `ProfileViewCase.addFriend` / `removeFriend` stay unchanged for the profile screen.
- `GraphPersonContextCubit._setTrust` (`graph_person_context_cubit.dart:113-152`) delegates to the case: it patches `selectedProfile` speculatively (and calls `onProfilePatched`, `graph_screen.dart:41`, with the speculative profile), emits no `trustLoading`, and on a definitive rejection or exhausted retry reverts to the last acknowledged profile and shows the "Trust change not saved" snackbar with Retry. l10n `graphTrustNotSaved`, `graphTrustRetry` (en, ru). Skill: `material-3-flutter`.
- No graph, field or profile read is triggered by the write. The field consequences come from the existing lazy global hint (ARCH §7.3).
- **Tests first:**
  - domain: toggle → overlay immediately; exactly one `setLike`, zero `fetchById`; toggle, toggle back before the ack → one in flight plus one pending, final value wins, an equal value is not resent; transport failure → retries with the same amount; rejection → revert plus notice; exhausted → revert plus notice; logout mid-flight → cleared, no further request;
  - domain (fake clock): overdue → one notice at 15 s;
  - widget (Constellation and graph screen): the toggle flips with no progress indicator; on failure it flips back and the Retry snackbar re-issues the intended value.
- **Acceptance:** CT graph and constellation green; the `trustLoading` state field is removed (`rg "trustLoading" packages/client/lib/features/graph` is empty); LINT clean.
- **Depends:** U04 (ports), U51 (shared notice widget and constant).

### U53 Perf fixture realism and D8 write re-measure (ARCH §7.6 rev 10)
- `test/perf/perf_fixture_matrix.dart`: mirror the MeritRank fixture edges into `user_trust_edge` **before** the timed attempts (today after them, `:344-370`), for every trust fixture including `apply_batch_*`, so FULL and ANCHORS read realistic trust tables. Re-run U41 and record the new read numbers; recalibrate a read budget only with owner approval.
- Re-measure the D8 `publication_burst` load level (U26 part 2/3 setup, same host class) on the U50 write. Record the write decomposition (fz1w fields) and the write p95 against the 70 ms budget; then run the `capacity` level once on the first configuration that passes, as U26 part 2/3 recommends.
- **Tests first:** a fixture test asserting that `user_trust_edge` row count equals the mirrored MR edge count before the first timed attempt.
- **Acceptance:** the journal records fixture reads, D8 write p95, staleness and capacity-level FULL/s with ≥ 30% headroom, or a blocked entry with evidence.
- **Depends:** U50, U41. Gates U26.

### U54 Pinned persons outside the visible set (ARCH §5.10; D15)
- Server, `data/repository/constellation_anchor_projection_reader.dart`:
  - `_loadAuthorizedAnchors` (`:227-297`) keeps person anchors regardless of the visible set and drops them only on a block in either direction (the blocked-CTE predicate, `constellation_anchor_repository.dart:256-260`). Request anchors keep the read wall (`:232-235`, `:266-269`).
  - Remove the visibility filter on person anchors in `readPrepared` (`:138-142`) and in `prepare`'s holder set (`:80-85`). Both remain only for reads once U50 lands.
  - Trust edges and the support closure still join only the viewer and visible peers (`:75-79`, `:392-402`). Profiles are fetched by id for every pinned person (`:405-412`).
  - The pinned peer record gains `visible: bool`. Server entity, GraphQL type and client mapper are updated, plus the FULL snapshot reader where it embeds the anchor projection.
- Client:
  - `composeConstellationPresentation` keeps non-visible pinned persons as kept peers (`constellation_anchor_composition.dart:206-208`, `:283-303`), and `resolveAndCapConstellation` (`constellation_cap_policy.dart:10-89`) never drops them;
  - a pinned person with `visible: false` is drawn at the pin with no path, no residual stub and no satellites (ARCH §5.10);
  - `docs/features/constellation.md` gets one sentence under "Pinned placement and request state" when this lands.
- **Tests first:**
  - pg: a pinned person who lost visibility (trust withdrawn; MR epoch change) is returned by ANCHORS and FULL with `visible: false` and a profile;
  - pg: a block in either direction hides them, and unblocking shows them again;
  - pg: unpin removes them;
  - pg: a pinned Request that becomes unreadable, deleted, unpublished or blocked disappears;
  - pg: the non-visible person's Requests are not added to the field;
  - pg: trust edges contain no edge to the non-visible person;
  - domain and widget: the node is drawn at its pin with no path and no stub, survives the peer cap at N = 300, and has no satellites.
- **Acceptance:** ST (with pg) and CT constellation green; LINT clean; the owner's answer to the Request read-wall question is recorded in the journal (default: no override).
- **Depends:** U12, U50 (the reader is read-only after U50), U51. Gates U26.

## Dependency graph (for beads)

```
U00 → U01 → U02 → U03 → U07 → U08
U00 → U04 → U05, U09 ; U06 ; U03,U04 → U09
U00 → U10 → U11 → U12 → U13 → U14 ; U10 → U15 → U16 ; U16 → U17 ; U12 → U18
U14,U16,U06,U09 → U19 → U20 → U21 → U22 ; U21 → U23
U08,U21,U23 → U24 → U25 → U26 ; U17 → U26
U02 → U27 ; U27 → U28 → U29 (also U24) → U30 → U31 ; U29 → U32 ; U07 → U33
U26,U28 → U34 → U35
U30 → U36 → U37 → U38 → U39
U00 → U41 ; U41 → U13, U15, U17, U18 (perf gates) ; U41,U12 → U42, U44 ; U17 → U43
U43 → U26 ; U42,U44 → U26 ; U45 → U26 ; U46 → U13 ; U41 → U46 ; U42,U44 → U40
U41 → U47 ; U47 → U26 ; U47 → U48 (optional)
U13,U14,U15 → U50 ; U50,U21,U23,U24,U25 → U51 ; U04,U51 → U52 ; U50,U41 → U53
U12,U50,U51 → U54
U50,U51,U52,U53,U54 → U26
all → U40
```
