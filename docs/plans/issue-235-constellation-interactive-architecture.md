# Constellation: always-interactive architecture (issue #235 and beyond)

Status: **architecture, rev 9**, 2026-10-06. Rev 9: measurement run 4 traced the dense-scale cost to MR walks-cache thrash (`MERITRANK_WALKS_CACHE_SIZE=200` < working set). §7.4a is downgraded to optional. Rev 8 adds: D8 confirmed by the owner; measurement runs 2–3 (dev copy and synthetic dense data); the visible-set cache promoted to required (§7.4a); the MR connector deadline shipped upstream (pgmer2 0.8.3).

- Rev 1/2 (commit `3795be0c6`): proposal plus the owner's decisions.
- Rev 3: layer-mapped architecture.
- Rev 4 and rev 5: apply review rounds 1 and 2 (codex `gpt-6.1-sol`, high).
- Rev 6+: server-performance review rounds 3 and 4.
- Every finding and its resolution is in `issue-235-constellation-interactive-review-record.md`.
- Implementation plan: `issue-235-constellation-interactive-implementation-plan.md`.

Related: #231, #232, #233, #234, #235. The interim fix `67ee9fa53` releases the anchor write slot after the mutation, not after the recovery read.

---

## 0. Owner decisions (binding)

| # | Decision |
|---|---|
| D1 | A node whose write failed stays where the user put it, marked **"not saved"**. The copy says it is a server-side problem. Actions: **Retry** and **Discard my move**. |
| D2 | A **"Re-arrange"** action re-lays out free nodes; user-placed nodes stay fixed. It is visible only after the user has moved something in this field. |
| D3 | The server protocol phase comes before render layering. |
| D4 | The outbox lives in memory only; nothing is persisted on the client. |
| D5 | **Whole-graph freeze** while a node is in hand. Buffered data is applied after release as one smooth transition. |
| D6 | Acceleration structures are chosen by benchmark; nothing is built unless it measurably wins, including build and invalidation cost. |
| D7 | Adaptive time slicing: an AIMD batch controller with a 4 ms setpoint and a hard cap. |
| D8 | **Capacity and freshness contract (confirmed by the owner 2026-10-06).** Declared population: **1,000** concurrently active sessions. Staleness bound for *global* invalidations (trust and MR publication): **≤ 5 min**, refreshed lazily while the field is visible (§7.3). Targeted invalidations (own Requests, anchors, blocks) keep their current freshness. |

## 1. Problem and invariants

After a drop, the next drag panned the camera until the anchor write *and* a full projection re-read finished. The root cause is systemic: **the user's hand waits for the network, the layout, or a rebuild** (§2). These invariants define "done", and each maps to tests in §9.

- **I1. Input is never gated on I/O.** Draggability depends only on node kind and ownership.
- **I2. While a node is in hand, the committed scene holds still (D5).** No refresh, recompose, layout, ack, rebase or running transition changes any node during a drag. Only the interaction presentation moves: the dragged cluster, hover and drop target. A resize re-projects the camera and never aborts the drag.
- **I3. Positional stability.** A user-placed node moves only by the user's hand, an explicit Discard or Re-arrange. A failed write doesn't move it (D1), and neither does a refresh. Missing or filtered rows are never treated as deletion evidence. A free node moves only when its inputs change: minimally, and only that node animates.
- **I4. Frame budget (N = 300, web profile build, mid-range laptop).**
  - drag frame and pan/zoom frame: under 8 ms of UI-thread work each;
  - no task over 50 ms anywhere in the drop → ack → reflow pipeline.
- **I5. Drop to next drag possible: 0 frames.** Drop to persisted: one request, with no follow-up read on the happy path.
- **I6. One network effect per user intent.** A cluster drop is one request. Your own echo is never refetched. A write needs no recovery read. Reads are single-flight and coalesced, and they pause while the tab is hidden.
  - Versioned "not modified" reads are **deferred** (§7.4). They are not required to meet I6.

## 2. Current state (verified 2026-10-06)

`C` = `packages/client/lib/features/constellation/ui/bloc/constellation_cubit.dart` (3,171 lines). `AC` / `FC` = `.../domain/use_case/constellation_{anchor,field}_case.dart`. `GV` = `packages/force_directed_graphview/lib/src/`. `SR` = `packages/server/lib/data/repository/constellation_field_snapshot_reader.dart`.

**Gesture**
- `isNodeDraggable` → `C.canDragNode` → `placementActionsEnabled`, which includes the case's write slot. While it is false the node acts as empty canvas, so the gesture pans.
- Camera gating is applied post-frame (`GV/graph_view.dart:299-322`).
- A resize aborts the drag (`GV/controller.dart:915-922`).
- The tap resolver is dead: `identical()` compares against a fresh snapshot (`constellation_body.dart:779-783`, `GV/scene_controller.dart:55`).
- The package already has a selective touch/stylus recognizer to build on (`GV/widget/node_drag_gesture.dart:516`).

**State**
- Single-flight write slot; a concurrent write is discarded.
- Optimistic state is visual only.
- Deferral is partial: it covers the ANCHORS hint path only, and `load()` doesn't defer.
- About 5–6 emits per drop. FULL is composed twice (FC + C).
- The composer listener recomposes on every pointer move, plus a 4 s poll.
- The cubit calls repositories and ports directly: `ForwardRepository.fetchForwardCandidates` (C:719), `ForwardRepository.offerHelp` (C:2268) and `ConstellationMemberWebsPort`.

**Domain purity**
- `domain/constellation_layout.dart:2` imports `dart:ui` (`Offset`, `Size`), and so does `features/graph/domain/layout/radial_hop_positions.dart:3`.
- `constellation_anchor_composition.dart:2` imports `NodeDetails` (Flutter foundation).
- These are existing violations of the "domain is pure" rule.

**Layout**
- Greedy placement over about 66 candidates against all obstacles: O(K·N²), and a single node's placement is an unbounded unit (`constellation_layout.dart:609`).
- Full recompute on every reconcile, including selection.
- Synchronous on the UI thread.
- Prior positions are soft hints only.
- A global 350 ms tween.
- The algorithm object is rebuilt per body build, which re-requests layout.

**Render**
- A whole-tree `AnimatedBuilder` per controller notify.
- Edges always repaint, including on camera ticks.
- O(L²) label placement per pan frame.
- The body rebuilds on `graphRevision`.

**Server**
- Mutations return `{anchor, revision}` only, which forces an ANCHORS read that pays the full visibility cost.
- No batch mutation.
- The per-row NOTIFY carries no revision. An absent-target delete updates the cursor and emits on its own (`constellation_anchor_repository.dart:356`).
- Repeating a write bumps revision and `placed_at` (`m0193.dart:1392`).
- `direct_trust_current_version()` reads sequence `last_value` (`m0193.dart:1617`), which is not an MVCC content version.

**Wire**
- V2 operations must be listed in `_tenturaDirectOperationNames` (`packages/client/lib/data/service/remote_api_client/build_client.dart:265-268`).
- Realtime kinds are a closed enum (`packages/client/lib/domain/entity/realtime/realtime_entity_change.dart:9`).

## 3. Target architecture: overview

```
                 ┌──────────────────────── UI layer (screen-owned) ────────────────────────┐
 pointer ──────► │ ConstellationInteractionController (gesture state machine, drag cluster)  │
                 │        │ PlaceIntent / Cancel / Retry / Discard                            │
                 │ ConstellationCubit (chrome)        ConstellationSceneController           │
                 │  filters, selection, sheets,        GraphController, SceneUpdateGate,      │
                 │  notices, badges                    layout job driver, transitions,       │
                 │                                     Flutter⇄domain geometry adapters      │
                 └──────────▲───────────────────────────────▲───────────────────────────────┘
                            │ Freezed domain states/streams │ pure calls
                 ┌──────────┴──── Domain layer (account-owned singletons + pure code) ───────┐
                 │ ConstellationFieldStoreCase          ConstellationPlacementCase              │
                 │  confirmed field+anchors,             outbox (per-target slots), flush,     │
                 │  coverage revision, single-flight     dedupe ids, settlement, retry policy  │
                 │  refresh, account generation                                               │
                 │ pure: desiredAnchorProjection · composeConstellationPresentation (memoised) │
                 │       ConstellationLayoutEngine (stable, incremental, bounded work units)  │
                 │       SpatialIndex · AdaptiveSliceController (AIMD maths)                   │
                 └──────────┼───────────────────────────────────┼─────────────────────────────┘
                 ┌──────────▼──────── Data layer ───────────────▼─────────────────────────────┐
                 │ ConstellationRepository (FULL/ANCHORS)   ConstellationAnchorRepository.apply │
                 └─────────────────────────────────────────────────────────────────────────────┘
```

Three rules hold it together:

1. **Desired = confirmed ⊕ unresolved local intent.** The UI renders desired state and never waits for the server.
2. **The interaction controller owns the hand.** Input gates when data reaches the scene, through the freeze gate; data never gates input.
3. **Layout is pure, incremental and resumable domain code.** The UI decides only *when* to run bounded steps.

## 4. Layer map (Clean Architecture placement)

Client paths are relative to `packages/client/lib/features/constellation/` unless they start with `lib/`.

### 4.1 Client: domain (pure Dart: no Flutter, no `dart:ui`, no Ferry, no `data/` or `ui/` imports)

| Component | Path | Kind | Notes |
|---|---|---|---|
| `PlacementOp`, `PlacementSlot`, `PlacementTargetState`, `PlacementOutboxState` | `domain/entity/placement_outbox.dart` (new) | Freezed | §5.1 |
| `desiredAnchorProjection(confirmed, outbox)` | `domain/placement_overlay.dart` (new) | Pure function | §5.2 |
| `ConstellationAnchorApplyResult` | `domain/port/constellation_anchor_repository_port.dart` (extended) | Freezed port DTOs | `beforeRevision`, `afterRevision`, per-op results, full `anchorProjection` (§7.1) |
| `ConstellationFieldStoreState` | `domain/entity/constellation_field_store_state.dart` (new) | Freezed | Confirmed field, anchor projection, `coveredRevision`, generation |
| `ConstellationFieldStoreCase` | `domain/use_case/constellation_field_store_case.dart` (split from FC and the read half of AC) | Use case, `UseCaseBase`, `@singleton` | §5.3 |
| `ConstellationPlacementCase` | `domain/use_case/constellation_placement_case.dart` (split from the write half of AC) | Use case, `UseCaseBase`, `@singleton` | §5.1 |
| `ConstellationMemberWebsCase` | `domain/use_case/constellation_member_webs_case.dart` (new) | Use case | Wraps the existing port |
| `ForwardCase.offerHelp` | `features/forward/domain/use_case/forward_case.dart` (extended) | Use case | The cubit stops calling `ForwardRepository` (C:719, C:2268) |
| `ConstellationLayoutEngine` | `domain/layout/constellation_layout_engine.dart` (split from `constellation_layout.dart`) | Pure | §5.5 |
| `SpatialIndex` with `BruteForceIndex` and benchmark winners | `domain/layout/spatial_index.dart` (new) | Pure | D6 |
| Domain geometry and node DTOs | `domain/layout/layout_geometry.dart` (new) | Pure records | `({double x, double y})`, `({double w, double h})`, rect, `LayoutNodeSpec`. Replaces `dart:ui` `Offset`/`Size` and `NodeDetails` inside domain |
| `radial_hop_positions.dart` | `features/graph/domain/layout/` | Pure | `dart:ui` replaced by domain geometry |
| `composeConstellationPresentation` | `domain/constellation_anchor_composition.dart` | Pure | Drops the `NodeDetails` import (emits `LayoutNodeSpec`), memoised on input identity |
| `AdaptiveSliceController` | `lib/domain/scheduling/adaptive_slice_controller.dart` (new) | Pure | AIMD maths; inputs are measured `Duration`s |
| `RealtimeEntityKind.constellationField`, `RealtimeEntityChange.revision` | `lib/domain/entity/realtime/realtime_entity_change.dart` (extended) | Shared entity | Closed-enum mapping plus a decoded `revision` extra |
| `ConstellationAccountPort` | `domain/port/constellation_account_port.dart` (new) | Port | `currentAccountChanges` stream, following the `AttentionAccountPort` precedent (`lib/domain/attention/attention_case.dart:52-70,194`) |
| `ConstellationProjectionParams` | `domain/entity/constellation_projection_params.dart` (new) | Freezed | `(context, normalised membership filters)`. Every projection, request and result is bound to one params generation |
| `ClockPort`, `OpIdPort`, `WakeUpPort` | `lib/domain/port/` (new, shared) | Ports | Injectable adapters in `lib/data/service/`; test replacements in mocks |

`ConstellationAnchorCase` and `ConstellationFieldCase` (client) are **removed** once the split lands. `di.config.dart` is regenerated, never hand-edited.

**Time, randomness and wake-ups.** These go through Injectable-bound ports (`ClockPort`, `OpIdPort` with UUID v4, `WakeUpPort` for timers), not bare function parameters: the manually constructed cubit's optional clock doesn't establish DI registration. The domain keeps only the retry *policy* (backoff schedule) and the AIMD *maths*.

**Lifetime.** Both cases are application-lifetime `@singleton`s whose *contents* are account-scoped. GetIt has no account scope here (`lib/app/di/di_current.dart:12`). The store subscribes to `ConstellationAccountPort` **independently of screen leases**. On replacement or logout it immediately:
- resets the generation;
- cancels timers and queued work;
- clears the outbox.

Old-account operations are never sent or retried under the replacement account's credentials.

### 4.2 Client: data

| Component | Path | Change |
|---|---|---|
| `ConstellationAnchorRepository` | `data/repository/constellation_anchor_repository.dart` | `apply(List<PlacementOp>)` → `ConstellationAnchorApplyResult`. The old upsert/delete are removed in the same release. |
| GraphQL | `data/gql/constellation_anchors_apply.graphql` (new) | Codegen via `build_runner` |
| Routing | `lib/data/service/remote_api_client/build_client.dart` | Add `ConstellationAnchorsApply` to `_tenturaDirectOperationNames`, and remove `ConstellationAnchorUpsert` / `ConstellationAnchorDelete` |
| Realtime decode | The realtime WS mapper | Decode `revision` and the `constellation_field` kind |
| Mappers | `data/model/` | Ferry → domain via `toEntity()` |
| Mocks | `*_repository_mock.dart` | `env: [Environment.test], order: 1` |

### 4.3 Client: UI (screen-owned, disposed with the screen)

| Component | Path | Responsibility |
|---|---|---|
| `ConstellationCubit` | `ui/bloc/constellation_cubit.dart` (shrinks) | Chrome state only. Injects only use cases: store, placement, member-webs, forward. |
| `ConstellationSceneController` | `ui/scene/constellation_scene_controller.dart` (new) | Owns `GraphController`, `SceneUpdateGate`, the layout job driver and transitions. Adapts domain geometry ⇄ `Offset`/`Size`/`NodeDetails`. |
| `SceneUpdateGate` | `ui/scene/scene_update_gate.dart` (new) | The D5 freeze, §5.4 |
| `ConstellationInteractionController` | `ui/scene/constellation_interaction_controller.dart` (new) | Gesture state machine, drag cluster, camera capture, §5.4 |
| `FrameSliceScheduler` | `lib/ui/utils/frame_slice_scheduler.dart` (new) | Drives resumable domain work with `Stopwatch` plus `SchedulerBinding`, §5.6 |
| `ConstellationPlacementMarker` | `ui/widget/constellation_placement_marker.dart` (new) | "Not saved" / "saving…" marker, Retry/Discard; design-system tokens, l10n strings |
| Re-arrange | `ui/widget/constellation_camera_controls.dart` | Visible when `hasUserPlacements` (D2) |
| Composer | `ui/screen/constellation_screen.dart` | Composer `BlocListener` gets a `listenWhen`. Composer positions go through the interaction controller's per-node listenables. |
| `force_directed_graphview` | `packages/force_directed_graphview/lib/src/**` | Generic UI package changes, §5.7. No Tentura imports. |

### 4.4 Server

Paths are relative to `packages/server/lib/`.

| Component | Path | Kind | Change |
|---|---|---|---|
| `constellationAnchorsApply` | `api/controllers/graphql/mutation/mutation_constellation_anchor.dart` | API | The only anchor write; the old upsert/delete are removed |
| Inputs and outputs | `api/controllers/graphql/input/input_field_constellation_anchor_op.dart` (new), `custom_types.dart` | API | `InputField*` list pattern; never `.nonNullable()` on a list type |
| `ConstellationAnchorCase.apply` | `domain/use_case/constellation_anchor_case.dart` | Use case | Envelope validation (count, duplicate ids, duplicate targets); depends on the port only |
| `ConstellationAnchorRepositoryPort.applyBatch` | `domain/port/constellation_anchor_repository_port.dart` | Port | → `AnchorApplyBatchResult` |
| `ConstellationAnchorRepository.applyBatch` | `data/repository/constellation_anchor_repository.dart` | Data | One **REPEATABLE READ, READ WRITE** transaction, configured before its first query, with the mutating-user context preserved. Inside it, in order:
1. **Prepare** visibility and geometry-independent projection inputs *before* taking the cursor lock: visible set (one memoised computation per viewer and context), trust edges, profiles, pinned-beacon readability.
2. Cursor `FOR UPDATE`.
3. **Batch-loaded** dedupe records and target watermarks (one query each).
4. Per-op authorization from the **shared memoised visibility** plus current block predicates, in input order. Today `constellation_anchor_upsert_authorization.dart:42` calls `person_visible_peers_symmetric` per op and bypasses the memo.
5. Conditional writes, watermarks, op log.
6. Final projection assembled from the prepared inputs.

**Contention policy.** Under RR, another writer committing a cursor change after our snapshot makes `FOR UPDATE` fail with `40001`, and the prepared work is wasted. Same-viewer concurrency is bounded by the client outbox (one in-flight request per tab), so collisions need several tabs or devices of one person writing at once. **Prepare-first is the default**, gated by a contention benchmark (2/4/8 concurrent tabs, sustained writes, cold preparation, cascades) that measures attempted vs completed transactions and exhausted retries. If the gate fails, the repository switches to **lock-first** (cursor `FOR UPDATE` as the first statement): failures become cheap, at the cost of a longer hold. A cross-isolate per-viewer writer queue was rejected as disproportionate (review record, round 4 #1).

**Prepared inputs** cover the existing anchors **plus all requested upsert targets**. The potential holder/support closure is computed from the prepared trust edges, and only the required profiles and beacon records are batch-fetched. Readability is cached by beacon id for both authorization and hydration. After the lock and the writes, the final anchor rows are re-read and the complete projection is assembled from the prepared inputs.

**Degraded visibility ≠ empty visibility.** m0222 fails closed to an empty set when MR is unavailable. For `applyBatch` such a result is a **transient error**: the batch aborts with a retryable error, the client sees `commitUnknown`, and it is **never** recorded as an op-log rejection.

The whole transaction is retried on serialization failure or deadlock, and any failure discards all prepared inputs. Backoff runs after rollback and outside the DB connection. Retries use bounded jitter with an end-to-end deadline; today's helper retries once, immediately (`data/database/postgres_serialization_retry.dart:8`). An existing anchor alone never authorizes a move after visibility revocation. A new `TenturaDb.withMutatingRepeatableRead` wrapper is needed, because `withMutatingUser` (`tentura_db.dart:194`) sets no isolation level and `withReadSnapshot` is read-only. |
| Anchor projection reader | `data/repository/constellation_anchor_projection_reader.dart` (new; the anchor half extracted from SR) | Data helper | Shared by ANCHORS reads and `applyBatch`; reuses the tx's m0222 memo |
| Migrations `m0223`–`m0225` | `data/database/migration/m0223.dart` … `m0225.dart` (new), each registered in `_migrations.dart` (part list plus registry) | SQL | m0223: tables `constellation_anchor_op_log` and `constellation_anchor_target_watermark`. m0224: deferred anchor and cursor NOTIFY triggers with a canonical envelope. m0225: field-hint producers (§7.3). m0193 is left unchanged. |
| Realtime fan-out | `api/controllers/websocket/path_handler/websocket_path_entity_changes.dart` | API | Extra validation refactored **per kind**: today it assumes seen timestamps (`:35-46`). Explicitly forwards `revision` for `constellation_anchor`, and forwards the `constellation_field` kind. |
| Dart absent-delete notify | `constellation_anchor_repository.dart:356-384` | Data | **Removed.** The cursor trigger covers it. |
| Lean profiles | `data/repository/user_profile_batch_lookup.dart` | Data | One-query name, handle and image |
| Version gate | `env.dart` `kDefaultMinClientVersion` | Config | Raised together with the client semver and the web cache-buster |

Authorization and read filtering keep their semantics. Leak and oracle hardening stays deferred per project policy, and this plan neither fixes nor regresses it.

## 5. Component contracts

### 5.1 `ConstellationPlacementCase`: the outbox

```dart
@freezed sealed class PlacementOp with _$PlacementOp {
  const factory PlacementOp.upsert({required String clientOpId, required String clusterId,
      required ConstellationAnchorTarget target, required ConstellationAnchorPosition position,
      ConstellationAnchorRevision? ifRevision}) = PlacementUpsert;      // ifRevision: compensation only
  const factory PlacementOp.delete({required String clientOpId, required String clusterId,
      required ConstellationAnchorTarget target, ConstellationAnchorRevision? ifRevision}) = PlacementDelete;
}
enum PlacementSlotStatus { queued, inFlight, commitUnknown, rejected }
@freezed abstract class PlacementSlot with _$PlacementSlot {
  const factory PlacementSlot({required PlacementOp op, required PlacementSlotStatus status,
      @Default(0) int attempts, String? reasonCode,
      ConstellationAnchor? preOpConfirmed}) = _PlacementSlot;   // captured for Discard
}
@freezed abstract class PlacementTargetState with _$PlacementTargetState {
  const factory PlacementTargetState({PlacementSlot? inFlight, PlacementSlot? latestPending}) = _PlacementTargetState;
}
@freezed abstract class PlacementOutboxState with _$PlacementOutboxState {
  const factory PlacementOutboxState({
    required Map<ConstellationAnchorTarget, PlacementTargetState> targets,
    required bool hasUserPlacements,                       // D2
    required int generation,
  }) = _PlacementOutboxState;
}
```

Public API: `changes`, `current`, `place(parent, position, companions)`, `unpin(target)`, `retry(target)`, `discard(target)`.

**Rules**

- **R1. Slots per target.**
  - Each target has independent `inFlight` and `latestPending` slots. `place` / `unpin` replace `latestPending` (last writer wins).
  - Status, attempts and reason belong to the slot's `clientOpId`.
  - Desired position comes from `latestPending`, otherwise from an unresolved `inFlight`.
  - Settlement updates only the matching op.
  - Terminal settlement (`ok`, or `rejected`) releases the dispatch slot. A rejected intent stays visible until Retry, Discard or supersession.
  - **Retry of a `rejected` op** creates a **new** `clientOpId`, because the old id's recorded rejection would replay forever. **Retry of `commitUnknown`** keeps the original id and fingerprint.
  - **Promotion:** a successor on the same target dispatches only after its predecessor's outcome is resolved. An exhausted `commitUnknown` blocks dispatch for **that target only**; other targets keep flushing. New input is always accepted locally and shown immediately.
- **R2. Batching.**
  - One request is in flight per viewer.
  - A flush takes queued slots in bounded batches, **cut only at cluster boundaries**: a cluster is never split.
  - Last-writer-wins removes superseded targets from unsent clusters.
  - The server cap is 64 ops, and the domain drag-cluster policy limits a cluster to 64 targets, so a cluster always fits.
- **R3. Settlement**, by `clientOpId`, published atomically with the confirmed adoption in one store transition (§5.3):
  - `ok`: the slot is removed, and the row reaches confirmed through the store.
  - `rejected`: the status becomes `rejected` with `reasonCode`. The node stays put (D1).
- **R4. Transport error or timeout.**
  - In-flight slots become `commitUnknown`: the write may have committed.
  - Automatic retry resends the **same `clientOpId`s** with jittered exponential backoff (1 s → 30 s). Server deduplication makes the replay safe (R9).
  - After 3 attempts the slot stays `commitUnknown`. The marker shows "not saved" (D1) and Retry continues manually.
  - Catch-up or reconnect triggers an immediate retry.
- **R5. Refresh never removes local intent.**
  - A refresh, a missing row or a filtered row is not deletion evidence.
  - Slots are removed only by matching settlement, explicit Discard, or an account or generation reset.
  - A server-confirmed unavailable target (rejected `target_unavailable`) keeps the local placement with the D1 marker and cannot recreate a deleted entity.
- **R6. Coverage and echo suppression** (implemented in the store, §5.3):
  - an echo is ignored only when its `revision ≤ coveredRevision`;
  - any uncovered hint triggers one coalesced ANCHORS resync, including exactly `coveredRevision + 1`;
  - hints that arrive while a request is in flight are buffered and evaluated after settlement.
- **R7. Discard.**
  - **Queued or `rejected`:** drop the slot. Desired state falls back to confirmed.
  - **`commitUnknown`:** replay the same `clientOpId`. A replay either returns the recorded result or executes and records the original op. There is no "never committed" answer.
    - `REJECTED`: drop the discarded intent.
    - `OK`: compensate.
  - **Compensation:**
    - Every `OK` result carries `resultingTargetRevision`, for DELETE as well. The server keeps a per-(viewer, target) **mutation watermark** that survives deletion (`constellation_anchor_target_watermark`).
    - The compensating op (an upsert restoring `preOpConfirmed`'s position, or a delete when the baseline was absent) carries `ifRevision = resultingTargetRevision`. The server compares it with the watermark under the cursor lock. On a mismatch it returns `REJECTED(conflict)`, which the client drops: newer server state wins.
    - `preOpConfirmed` is captured **immediately before first dispatch**, after preceding ops on the target have settled.
    - An unknown outcome of a compensation follows the same replay rules.
    - Newer local intent cancels only an **unsent** compensation. One already dispatched must settle before its successor dispatches.
  - **`inFlight`:** mark it `discardOnSettle` and apply the same logic once it settles.
- **R8. Lifetime.**
  - The outbox is account-owned. It survives the screen closing, so memory-only ops can still settle (D4).
  - It captures `(accountId, generation)` before every request and retry, and drops stale completions.
  - A generation change (account replacement or logout only) clears it without writes.
- **R9. Idempotency** (server, mandatory).
  - `constellation_anchor_op_log(viewer_id, client_op_id, fingerprint, result, revision, created_at)`, with primary key `(viewer_id, client_op_id)`, is written in the same tx as the write.
  - A replay with the same fingerprint returns the recorded result and does nothing else. A different fingerprint is `REJECTED(op_id_reused)`.
  - **Retention: until account deletion** (FK `ON DELETE CASCADE` to the user). Rows are never purged on the mutation path. Time-based retention would need its own protocol, rejecting expired ids without executing them, and is out of scope.
  - **Row size bounded.** The log stores only the minimal per-op replay result (status, reason code, resulting target revision, position), **never a projection**. `client_op_id` ≤ 64 bytes; the fingerprint is a 32-byte digest. Only the viewer-leading primary key, with no secondary indexes unless a query demonstrably needs one.
  - Growth estimate: about 20 ops per user per day × 100k users ≈ 730M rows/year. This is measured in P2 (tuple and index bytes, WAL/op); hash partitioning by viewer is the prepared escalation, not a v1 requirement.

### 5.2 Desired state (pure)

`desiredAnchorProjection(confirmed, outbox)` overlays unresolved upserts and removes unresolved deletes. It also returns a side map `unsaved: Set<target>` covering `rejected`, `commitUnknown` with attempts ≥ 3, and anything in flight longer than 1 s (for the "saving…" cue).

Pinned records for a new pin come from the field snapshot (the node was on the field to be dragged) or from the ack's anchor projection. No other code path reads `confirmed` for presentation.

### 5.3 `ConstellationFieldStoreCase`: the one owner of server state

API: `lease()` returns a `StoreLease` (screen activation; disposing the lease detaches visibility interest), plus `changes`, `current`, `setVisible`, `setMembershipFilters`, `requestRefresh(reason)`, `settle(ConstellationAnchorApplyResult, settledOpIds)` and `requestAnchorsResync()`.

- **Account generation.** The store owns `(accountId, generation)`. The generation changes only on account replacement or logout; screen leases don't touch it. The placement case subscribes to it.
- **Single-flight refresh.** All triggers coalesce: realtime hint kinds, catch-up, resume, filters, preflight. The current debounce and spacing policy (220 ms / 2 s / 30 s) moves here. Catch-up yields **one** FULL. Hidden tabs fetch nothing, ANCHORS included.
- **Params binding.** Every projection is bound to `(account, generation, ConstellationProjectionParams)`. The batch request carries the current params. Results computed for obsolete params still settle their op ids, but their projection is ignored.
- **Coverage revision (R6).**
  - `coveredRevision` is the revision of the newest **complete** anchor projection held for the current params.
  - A batch result's complete projection at `afterRevision ≥ coveredRevision` **replaces** confirmed anchors and advances coverage directly. `beforeRevision` is diagnostic only, not a resync condition.
  - Per-op replay results (historical) settle ids but never overwrite the returned current projection.
  - An ANCHORS or FULL projection at revision ≥ current does the same.
- **Independent merge.**
  - FULL's non-anchor data (peers, requests, posts, edges) has its own **read sequence**: the newest issued FULL for the current params wins, whatever its anchor revision.
  - Anchor revision never establishes field freshness.
  - Field hints (`constellation_field`) always request FULL and are never suppressed by anchor coverage.
- **Refresh scheduling.** One pending refresh and one immutable retry-not-before deadline per params:
  - hints, resume and catch-up never shorten a server `RETRY_LATER` backoff, and never keep postponing an already scheduled refresh;
  - visibility is re-checked at dispatch;
  - an in-flight FULL satisfies coalesced triggers unless a newer invalidation arrived after it started;
  - reconnect replays of `commitUnknown` writes are jittered, and writes take priority over recovery reads;
  - the eventual catch-up FULL is preserved.
- `preflightRequestAction` reads `current`; the server validates at action time.
- **One emit per applied change.** Composition happens in the UI scene controller, not here.

### 5.4 Interaction controller and freeze gate (UI)

State machine:

```
idle ─down on draggable node─► pressing(node) ─slop─► dragging(cluster) ─up─► settling ─► idle
  │                                │ up (no slop) = tap                    │ cancel / lost capture / tab hidden
  └─down on canvas─► panning ─up─► idle                                     └─► idle (no PlaceIntent)
composing: sibling mode with a draft node, same freeze rules.
```

**Arbitration (§5.7.1).**
- A hit is classified synchronously at pointer down, and draggability is `isDraggableKind(node)`.
- The node owner keeps tap behaviour and starts movement only after slop.
- **Camera arbitration** distinguishes three sources:
  - gesture-origin pan/scale: blocked while a node owns the gesture, along with additional touch pointers;
  - wheel and trackpad signals: allowed, applied through an explicit camera API, and the captured grab point is re-projected;
  - programmatic updates.
  The generic package owns this arbitration, including the enclosing `InteractiveViewer` recognizers. Today's gating disables pan *and* scale via the viewer flags (`GV/graph_view.dart:317`).
- Pointer policies:
  - secondary button: context menu, never a drag;
  - a second touch pointer while dragging: ignored;
  - wheel or trackpad zoom while dragging: allowed, and it re-projects the drag;
  - pinch on canvas: camera.

**Freeze gate (D5).** Entering `dragging`:
1. freezes the committed scene revision;
2. **pauses** every running transition, preserving displayed positions *and unfinished destinations*. It must **not** reuse the existing destructive interaction stop (`GV/controller.dart:731`, called on capture at `GV/widget/node_drag_gesture.dart:393`);
3. **invalidates** outstanding layout jobs and publication tickets. Every queued publication callback re-checks scene generation, ticket and freeze state; today the accepted-layout microtask checks only disposal (`GV/controller.dart:611`);
4. starts coalescing store, outbox and composer inputs (the latest of each wins).

Every scene-facing widget consumes the **gated** scene revision: nodes, labels, edges, markers, chips. Only the interaction presentation updates: dragged cluster positions, hover and drop target.

Leaving `dragging` releases the gate **exactly once**, on drop, cancel, lost capture or tab hidden:
- **drop:** the `PlaceIntent` goes into the outbox first, then one combined compose and layout job, **rebased on the frozen displayed geometry including unfinished destinations**, and one replacement transition. If no inputs changed, the paused movement resumes from its current positions with no elapsed-time jump;
- **cancel:** no op is enqueued, and the dragged cluster animates back to its gated positions as part of the same combined transition;
- **account reset:** clears immediately and invalidates all prior work.

`settling` is purely visual. A new pointer down cancels it at its current positions.

### 5.5 `ConstellationLayoutEngine`: stable, incremental, resumable

```dart
final class ConstellationLayoutEngine {
  ConstellationLayoutEngine({required SpatialIndex Function() newIndex});
  /// Planning, dependency diffing, obstacle preparation and placement are
  /// phases of ONE resumable job; nothing unbounded runs before the first step.
  LayoutJob start(LayoutResult? previous, LayoutInput next);
}
abstract interface class LayoutJob {
  /// Runs at most [units] bounded work units (one candidate evaluation or one
  /// bounded obstacle-scan chunk). Returns true when the job has finished.
  bool step(int units);
  LayoutResult get result;   // valid when finished
}
```

**Stability contract (I3).**
- Fixed: anchored nodes plus nodes with unresolved local intent.
- Kept as hard constraints: free nodes whose inputs (ring, author, support path, footprint) are unchanged and which overlap nothing new.
- Re-placed by a minimum-displacement search starting at the old spot: free nodes whose inputs changed or that a new fixed node now overlaps.
- New nodes go into free space.
- A full plan runs only on first load, a filter change, or Re-arrange (D2, stable seed).

**Bounded units.** Candidate evaluation, obstacle scans and preprocessing are each resumable in bounded units. No single unit may exceed a measured worst case of 0.5 ms at N = 1000. Composition and final geometry publication are measured separately against I4, and sliced too if needed. The initial spatial index is brute force (D6).

**Spatial index (D6).** An interface with `insert`, `remove` and `queryOverlaps`. `BruteForceIndex` is the default and the test oracle; others land only if the benchmark proves a win.

**No layout** on selection, highlight or label-budget changes.

### 5.6 Adaptive time slicing (D7)

`AdaptiveSliceController` (pure):
- The setpoint is 4 ms and the hard cap is 8 ms.
- It keeps an EWMA of per-unit cost (α = 0.3). The first batch is `setpoint / ewma`, floor 1.
- AIMD: after a slice that finishes on time, add a fixed **+8 units**; after one over the setpoint, halve (floor 1).

`FrameSliceScheduler` (UI):
- Runs at most **one slice per frame**, enforced by a **frame permit** that idle and promoted callbacks share. `scheduleTask` schedules event-loop work, not one task per frame. The priority only controls eligibility (Flutter `scheduler/binding.dart:1465`).
- It checks the `Stopwatch` deadline after each bounded unit, so a slice stops at the setpoint even when the controller's estimate was wrong.
- Scheduling goes through `SchedulerBinding.scheduleTask(Priority.idle)`.
- If idle tasks are starved for more than 100 ms (Flutter suppresses idle tasks during animation), an **independent** wake-up (`WakeUpPort`) re-posts the job at `Priority.animation`. A job token prevents duplicate execution.
- Tests cover continuous animation and stalled-frame wake-ups.
- Pointer down pauses the job. A newer plan cancels it.

On web, all of this runs on the UI thread. A native isolate path is out of scope.

### 5.7 `force_directed_graphview` (generic package)

1. **Pointer arbitration.**
   - Extend the existing selective recognizer (`node_drag_gesture.dart:516`) into a pointer-aware owner recognizer for mouse as well, replacing the raw `Listener` path. It claims the pointer when the hit is a draggable node.
   - The camera's transform writes are synchronously gated during capture.
   - Tests: node tap, canvas pinch, added pointers, cancellation, zero camera movement during a node drag.
2. **Per-node position listenables.**
   - Stable, disposed-per-node `ValueListenable`s. Structural membership (node set) rebuilds separately from position updates.
   - **Coherent geometry and presentation revisions** are published for painting and hit testing.
   - `sceneRevision` (an `int`) replaces snapshot `identical()`, which fixes the tap resolver.
3. **Transitions.** `animateTo(targets, {skip})` tweens only nodes moved by more than 2 px, from their current positions. Non-destructive `pauseTransitions()` / `resumeTransitions()` preserve unfinished destinations and serve the freeze. There is no global tween.
4. **Stable algorithm identity.** Configuration compares a revision and never re-requests layout on rebuild. Existing layout tickets and presentation tokens are kept.
5. **Resize** never aborts a drag.
6. **Edge caching, only if measurement shows benefit** (phase P4 measures first).
   - The cached `Picture` excludes edges handled by the live painter (dragged and animating endpoints). It is invalidated by geometry revision and style, and replaced pictures are disposed.
   - Camera scale goes through the canvas transform. `Paint` objects are reused.

## 6. Data flows

### F1. Drop (happy path)
1. `up`, then the interaction controller emits `PlaceIntent(cluster)`.
2. `place` fills `latestPending` and emits. The gate is released once, with the combined input.
3. The scene controller composes (memoised) and starts one layout job (incremental: dropped nodes fixed, overlapped neighbours re-placed). The job runs in slices, then `animateTo` moves only the changed nodes.
4. The flush sends `apply` (one request). On the ack, the store settles in one transition: confirmed rows plus slot removal. Desired state is unchanged, so nothing changes visually and no layout runs.
5. The echo arrives with `revision ≤ coveredRevision`, so it is ignored.

### F2. Failure
- **Reject:** `rejected`, marker shown.
- **Timeout:** `commitUnknown`, auto-retry with the same ids; after 3 attempts the marker shows.
- The node never moves.
- **Retry** resends. **Discard** follows R7.

### F3. Data mid-drag
Coalesced in the gate, and nothing is drawn. On release: one combined compose, plan and transition.

### F4. Drag again during in-flight
The pointer always claims the node. The new op becomes `latestPending` for its target; the in-flight slot settles independently (R1).

### F5. Another tab writes B while this tab writes A
A's result carries the **complete** projection at `afterRevision`, which already includes B because the server serialises both writes on the cursor. It replaces confirmed anchors and advances coverage. B's hint (`revision ≤ coveredRevision`) is then ignored. If B commits after A, B's hint is uncovered and triggers one ANCHORS resync.

### F6. Catch-up or reconnect
One FULL. `commitUnknown` slots retry immediately.

### F7. Account change
Generation + 1. Outbox, gate and scene are cleared, and any drag is cancelled.

### F8. Tab hidden
- The store stops fetching. The outbox keeps flushing because the slots are account-owned.
- A drag is released as **cancel**.
- On resume: one refresh.

### F9. Screen closed during in-flight
The outbox settles in the background. The next screen lease picks up the current state, markers included.

### F10. Re-arrange
A full plan with a stable seed. No server write: free-node positions aren't persisted.

## 7. Server protocol

### 7.1 Batch mutation

```graphql
input ConstellationAnchorOpInput {
  clientOpId: String!  kind: ConstellationAnchorOpKind!          # UPSERT | DELETE
  targetKind: ConstellationAnchorTargetKind!  targetId: String!
  position: ConstellationAnchorPositionInput                     # required for UPSERT
  ifRevision: String                                             # compensation only (target watermark)
}
type ConstellationAnchorOpResult { clientOpId: String!  status: ConstellationAnchorOpStatus!  # OK | REJECTED
  reason: String  anchor: ConstellationAnchor
  resultingTargetRevision: String }                                # for every OK, DELETE included
type ConstellationAnchorsApplyResult {
  beforeRevision: String!  afterRevision: String!
  results: [ConstellationAnchorOpResult!]!
  anchorProjection: ConstellationAnchorProjection!   # same shape as the ANCHORS read, computed in-tx
}
mutation constellationAnchorsApply(ops: [ConstellationAnchorOpInput!]!,
    context: String!, showClosed: Boolean!, participatedOnly: Boolean!): ConstellationAnchorsApplyResult!
# projection params are sent so the returned projection matches the client's current params
```

**Envelope.** At most 64 ops. Duplicate `clientOpId`s or duplicate targets in one envelope are rejected before execution.

**Per op**, in input order:
1. dedupe lookup;
2. authorization;
3. `ifRevision` check;
4. write;
5. op-log row.

Authorization, validation and conflict rejections are per op. An unexpected database error rolls back the whole accepted set (transport error → `commitUnknown`). The transaction is REPEATABLE READ, READ WRITE, retried whole on serialization failure (§4.4). Its single snapshot makes the in-tx projection coherent. pg tests cover concurrent visibility changes, cascade deletes and concurrent anchor writes.

**Returned projection.** `anchorProjection` is the **complete** anchor projection at `afterRevision`, so client-side delta closure isn't needed. Its correctness test: it equals a fresh ANCHORS read at the same revision. An anchor ack never manufactures a FULL field version.

**No cheap-response fast path in v1.** "Position-only" moves don't prove unchanged support paths, readability or profiles. A cheaper response would need:
- an authenticated, params-bound baseline;
- proof that every reused component is still valid;
- `baseRevision` → `afterRevision` changes that include foreign writes and deletions, with coverage advancing only when applied to that exact baseline.

That depends on the deferred §7.4 dependency generations. Until then, the complete projection stays, and the cost is cut by **transaction-local reuse** (§4.4 step 1) instead.

### 7.2 Notifications

- The anchor and cursor triggers become deferred constraint triggers (`DEFERRABLE INITIALLY DEFERRED`).
- At commit they call the **strict** publisher with an identical **canonical envelope**: entity `constellation_anchor`, id and recipient = viewer, event always `update` (never `lower(TG_OP)`, which differs per statement today, `m0193.dart:2794`), and `revision` = the final cursor revision as a decimal string.
- Postgres collapses identical payloads within a transaction, so a batch delivers **one** hint per viewer. That covers mixed ops, cursor-only absent deletes (the Dart-side notify at `constellation_anchor_repository.dart:370` is removed), cascades and direct SQL.
- Publication is skipped when the viewer row was deleted in the same transaction.
- **Callback cost.** NOTIFY deduplication removes duplicate *messages*, not deferred-trigger *executions*: a 64-op batch would queue about 128 callbacks. Each deferred callback first checks a transaction-local publication marker keyed by `(viewer, final revision)`, using `set_config(..., true)`, and returns early when the marker is already set, so the strict publisher runs once per viewer per transaction.
- Metrics: callback count, publisher calls, commit latency, `pg_notification_queue_usage()`, listener → WS latency. NOTIFY commit locking stays global and every worker runs its own listener (`pg_notification_service.dart:88-93`). So benchmark concurrent notifying commits (transaction body and COMMIT latency separately), cursor-lookup counts, payload bytes, listener backlog, event-loop delay and slow listeners. Listeners never run inside long transactions.
- Fan-out forwards `revision` explicitly (§4.4). The client decodes it into `ConstellationAnchorRevision`, and coalescing keeps the highest revision.
- Row revision assignment and cursor locking are unchanged. This is new migration m0224; m0193 is not edited.
- Tests: mixed ops, cursor-only deletes, cascades, rollback (no hint), and the full PG → WS → client path.

### 7.3 Visibility hints

Explicit producers are added in m0225 and the server layer map:

- **Trust changes and MR publication** (the global epoch bump, `m0202.dart:39`) can affect viewers beyond the trust endpoints, so they invalidate **all connected authenticated viewers** with a payload-free global `constellation_field` hint. This stays until an affected-viewer algorithm is proven complete.
- **Block changes** invalidate both parties.
- Disconnected sessions are covered by catch-up.
- The client treats field hints as **non-urgent**: 30 s spacing plus jitter, coalesced, paused while hidden. **That bounds timing, not aggregate load.** Sustained demand is about `Q ≈ N_active × min(f, 1/30 s)`: 10k sessions with a publication every 10 s means about 333 FULL/s. So the server side is bounded too:
  - **Dirty generation.** Producers emit **one** global marker, never a per-viewer enumeration. Each server process coalesces markers into a dirty generation and broadcasts at most once per coalescing window (default 30 s, env knob), batched across sockets so the event loop is never blocked by one synchronous fan-out burst (`websocket_path_entity_changes.dart:110` today).
  - **Admission.** FULL reads pass a per-worker admission limit (bounded concurrency plus queue age; over the limit → `RETRY_LATER` with a backoff hint the client honours).
  - **Per-(viewer, params) single-flight** on the server, **isolate-scoped**: requests land on any worker (`app/app.dart:50-54`; fan-out is isolate-local, `websocket_path_entity_changes.dart:7`), so the residual duplicate factor is ≤ min(W, tabs). It applies **before** admission, so followers don't consume permits. The duplicate factor enters the capacity model. A cross-isolate coordinator is out of scope.
  - **Global hints are lazy (D8).** On a global marker the client marks the field stale and refreshes it at most once per D8 staleness window, only while the field is visible. It refreshes immediately when the user returns to the tab or opens Constellation. With 1,000 active sessions and a 5 min bound that is about 3.3 FULL/s. Without lazy refresh, 10k sessions would need about 333 FULL/s, against ≈ 27 tx/s for 8 workers × 300 ms.
  - A FULL started at generation g acknowledges only g. Changes during the read stay pending.
  - Resume and catch-up keep their FULL guarantee.
  - Endpoint-only invalidation is insufficient, so all-viewer invalidation stays until an affected-viewer algorithm proves completeness. Lazy-only refresh would change the active-field freshness contract and needs a product decision.
- Release requires load tests: publication bursts, reconnect bursts and concurrent tabs. Record aggregate FULL rate, queue age and maximum refresh staleness, with capacity for the declared active-session population plus at least 30% headroom.
- Field hints always request FULL.
- Tests: a trust change alters a third viewer's field; visibility is revoked during a drag (buffered by the freeze, applied on release).

### 7.4 Deferred: versioned reads (`ifVersion` / `notModified`) and cross-request caches

**Now: transaction-local reuse only.** Visibility, profiles, trust edges and beacon readability are reused within one request transaction (the m0222 memo plus in-Dart reuse).

m0222's memo re-checks a stamp containing sequence `last_value` (`m0222.dart:104-119`), which changes outside the RR snapshot, so unrelated trust churn can force recomputation mid-transaction. A follow-up migration adds a **frozen** mode: constellation RR transactions that cannot mutate trust set a tx-local flag, and after its first computation the memo ignores later stamp changes. Transactions that mutate trust keep explicit invalidation. This is still transaction-local, never cross-request. m0222's stamp (`direct_trust_current_version()` = sequence `last_value`) and its failure-empty result are **never** promoted to a cross-request cache.

**Later: cross-request caches.** A cross-request visible-set cache requires snapshot-consistent, transactionally maintained trust generations and a proven MR publication boundary. Raw visibility is cached separately from block filtering, or block generations are included. A per-beacon readability cache needs invalidation for every hierarchy and membership dependency of `beacon_can_read_content` (`m0193.dart:617`). Degraded results are uncacheable. A transactional **candidate** set (ordinary eligibility attributes, with current authorization still mandatory) is safe; a cached permission decision is not.

**Versioned reads** are deferred as follows (§7.4a is the exception that is now required).

These are **not in this plan's implementation scope**. A separate design must meet all of the following first:

- Tokens bind viewer, context, projection and normalised parameters to **transactionally updated counters** covering every returned datum and every authorization input, including post age, room seen, membership, profiles, blocks and MR state.
- Never use a sequence's `last_value` as a content version.
- The token and payload are computed in the same repeatable-read snapshot.
- There is an expiry bound for time-dependent results. Degraded or MR-failure snapshots are uncacheable (m0222's fail-closed memo returns empty sets on MR failure without an epoch change).
- Tests cover concurrent uncommitted writes, rollback, every dependency, expiry and MR recovery.

### 7.4a Visible-set cache across requests (optional; superseded by walks-cache sizing)

**History.** Run 3 measured `mr_mutual_scores` at **5–7 s** for V ≈ 1,000 and made this cache required. **Run 4** found the cause: the MR walks cache (`MERITRANK_WALKS_CACHE_SIZE=200` locally, on dev and in prod) was smaller than one read's working set (about 1,019 peer frames), so every read recalculated frames. With the cache sized to cover the working set, a warm `mr_mutual_scores` takes **47–61 ms** and FULL p50 is **154 ms** at V ≈ 1,000 (§7.5, U47).

**Now.** This cache is kept as an **optional** design for the remaining **cold** cost: about 2–2.4 s for the first read of a new ego after an MR restart or a walk-dirtying write. Build it only if that cold cost matters in production. The constraints below still apply if it is built.

**Design constraints** (the §7.4 "later" requirements, now binding):
- **Key:** `(viewer, ctx, mr_publish_epoch, trust_generation)`.
  - `trust_generation` is a **transactionally maintained counter row**, bumped in the same transaction as any trust, block or relationship change that can affect visibility. It is *not* a sequence `last_value`. A reader sees the generation that matches its MVCC snapshot.
  - The MR publish epoch marks when MR scores become those of a newer publication.
- **Storage:** a Postgres table `person_visible_set_cache(viewer_id, ctx, mr_epoch, trust_gen, peer_ids text[], computed_at)`. It is read and written inside the request's REPEATABLE READ snapshot, and a row is valid only if its key matches the snapshot's current values. It is shared by every worker and isolate, so there's no cross-isolate duplication.
- **Raw visibility only:** the cache holds MR-derived visibility. Block filtering stays live, or block changes bump `trust_generation`.
- **Fail-closed:** a degraded or MR-failure result (m0222's empty fallback) is **never** written. An expired or mismatched row is recomputed.
- **Correctness tests:**
  - concurrent uncommitted trust change → no stale hit after commit;
  - rollback → no bump;
  - a block in either direction;
  - an MR epoch bump;
  - MR failure → nothing cached;
  - parity with uncached visibility on fixtures.

### 7.5 Server read-path optimisation (priority order)

1. **Discoverable candidates (#233).** Today readability is applied before sort and LIMIT (`constellation_field_snapshot_reader.dart:709-722`), so the cost is about C × 1 ms for C candidates.
   - A partial index on `(user_id, id)` matching kind, publication, discoverability and lifecycle predicates (benchmark against the author-only index `m0193.dart:6567`).
   - A **keyset scan** in output order, evaluating readability in batches until cap + 1 readable results or exhaustion.
   - Never LIMIT before authorization.
2. **Reuse** authorized pinned-beacon hydration within the transaction. Today readability runs twice per pinned beacon (`:247`, `:639`).
3. **Lean profiles** (U18).
4. **Trust edges.** Today they span the whole visible set before graph-peer selection (`:370` vs `:86`), O(V²) in dense graphs.
   - Benchmark joins on the existing pair indexes, with EXPLAIN evidence before adding indexes.
   - Never silently truncate visibility, anchors or support paths.

**MR RPCs.** At most one `mr_mutual_scores` plus U fallback scores per distinct (viewer, context) per transaction, never per op. Fallback scores are batched where MR supports it.

**Measured 2026-10-06** (`issue-235-constellation-interactive-measurements.md`, local MR v0.11.1 + postgres-tentura v0.8.2):
- an MR RPC now costs **0.02–0.62 ms**, vs the ~88 ms Nagle stall of #231;
- `beacon_can_read_content` costs **0.25–0.36 ms** per call, vs ~1 ms on dev per #233; dev must be re-measured.

The happy-path latency concern is resolved locally; the failure-time bound below is not.

**Walks cache (run 4, U47).** `MERITRANK_WALKS_CACHE_SIZE` must cover **one read's working set**: the largest visible set + 1. Below that, `ego_read` pins peers in portions that evict one another and **recalculates frames on every read** (about 100× slower at V ≈ 1,000). Reverse scores are deliberately not cached across frame eviction (`meritrank-rust` `SERVICE_CONSISTENCY_PLAN.md` §2.7). The size is a per-host memory budget (about 1 MB per frame at 10k walks). A generation-checked reverse-score cache in MeritRank, which would let reverse scores survive frame eviction, is being done separately in `meritrank-rust` before this plan starts. It is outside this plan.

**Status:** the connector side shipped upstream as `Intersubjective/meritrank-rust` #89, pgmer2 **0.8.3** / `postgres-tentura:v0.8.3`. One absolute per-call deadline; waits interruptible by `statement_timeout`/cancel; `mr_rpc_attempts()`. Tentura adoption (image pin, budgets) is U45.

**MR deadlines (release blocker).** Today `MERITRANK_RECV_TIMEOUT_MSEC=60000` (`compose.dev.yaml:113`, `compose.prod.yaml:101`). The connector also retries once, has no write timeout, uses blocking DNS and per-read socket timeouts. A silent peer can therefore hold a worker's only DB connection for about 120 s, and a Dart timeout can't interrupt the blocking extension call (#231).

Release requires a **verified connector build** (`meritrank-rust/psql-connector`) with:
- **one absolute deadline** covering resolution, connect, write, the complete response read and reconnect;
- a **request-level MR budget** shared by all fallback calls, with retries consuming that same budget;
- PostgreSQL statement cancellation is not relied on unless connector interruption is demonstrated;
- on deadline expiry, the connection is released only after a confirmed rollback.

Tests: blackhole, stalled write, trickled response, recovery. Count actual network attempts, connector retries included.

**Discoverable keyset contract (U42).**
- Lexicographic `(user_id, id) > last_examined_key` pagination under one RR snapshot, preserving DB collation. The scan advances over **every** examined candidate, rejected ones included.
- Each readability batch is explicitly ordered. Collect cap + 1 eligible rows, preserving exclusions and participation filters. Overfetch is bounded.
- The partial-index predicate must be implied by every supported query variant (`constellation_field_selection.dart:100-109`; the older `constellation_field_repository.dart:207-214` differs and must be reconciled), prepared plans included.
- Readability work is about `min(C, ceil((cap+1)/readable_fraction) + overfetch)`. At readable_fraction → 0 it still scans C, which is why the gate is the candidate-query gain on eligible fixtures plus a whole-FULL regression limit, not a universal 50%.

### 7.6 Server capacity model and budgets

- **One DB connection per worker isolate.** Drift's pool is fixed at `maxConnectionCount: 1` (`tentura_db.dart:148`, `env.dart:764`, `WORKAROUNDS.md` §4), and web workers are separate isolates (`app/app.dart:50`). A worker's throughput is therefore about 1 / (mean transaction time). With 8 workers and 300 ms transactions that is only about 27 tx/s for **all** traffic.
  - **Measured (local, one worker, JIT debug, small graph):** FULL saturates at **≈ 36–38 req/s** and ANCHORS at **≈ 145–153 req/s**, already at concurrency 8. Beyond that, only queueing latency grows: FULL p50 goes from 27 ms to 820 ms at concurrency 32. This confirms the model empirically.
  - Eager 30 s refresh for 1,000 sessions (≈ 33 FULL/s) would saturate one worker. D8's lazy policy (≈ 3.3 FULL/s) leaves more than 10× headroom at local scale.
  - **Dev-copy data** (heaviest viewer: V = 76, payload 39 KB): one worker saturates at ≈ 22 FULL/s and ≈ 120 ANCHORS/s, with FULL p50 55 ms. **Dense synthetic data** (V ≈ 1,000): about 7 s per FULL, ANCHORS or person upsert with walks cache 200. With the cache sized to the working set (1,200): FULL p50 **154 ms**, ANCHORS 18 ms, upsert 47 ms (run 4).
  - Transaction duration is the primary capacity lever: prepare before lock, tx-local reuse, no long RR snapshots.
  - **Do not raise the pool size** without first fixing transaction affinity.
  - Admission limits apply before transaction entry.
  - **Worker-wide constellation DB scheduler.** Every constellation transaction (apply, ANCHORS, FULL) is admitted *before* it enters Drift. No refresh transaction is ever queued inside Drift.
    - Interactive mutations get priority over pending refreshes.
    - A measured reserved refresh share plus oldest-first fairness prevents refresh starvation.
    - Queue deadlines include all application and DB waiting.
    - Validate write p95 during publication storms, and the maximum refresh age during sustained writes.
- **Initial target budgets** on a declared reference machine. These are proposed, and are calibrated against the P2 baseline before becoming gates.

  | Operation | p50 | p95 |
  |---|---|---|
  | 1-op apply | 25 ms | 100 ms |
  | 64-op apply | 100 ms | 300 ms |
  | ANCHORS | 40 ms | 150 ms |
  | FULL | 100 ms | 300 ms |

  - Cursor-hold p95 ≤ 50 ms. Serialization retries under 1% when healthy.
  - Batch latency and amortised per-op cost are reported separately.
- **Measured per query family** (candidates, anchors, trust edges, mutation):
  - EXPLAIN (ANALYZE, BUFFERS, WAL);
  - rows rejected by authorization;
  - RPC count and query count;
  - spills;
  - WAL/op and HOT-update ratio;
  - connection queue time, cursor wait and hold, transaction age, retry count;
  - unrelated-endpoint latency while under load.
- **Write amplification.** B accepted ops ≈ 4B tuple mutations (anchor, cursor, watermark, log). Benchmark fillfactor and autovacuum for the cursor, anchor and watermark tables, and avoid indexing frequently changed revision or placement columns.
  - Size limits are enforced **in the schema**: `client_op_id` as `varchar(64)`, fingerprint as `bytea` checked to 32 bytes, replay result size-checked.
  - Replay, rejection, no-op and meaningful-write costs are recorded separately. HOT eligibility and achieved ratios are measured on aged tables.
  - Storage, vacuum and partitioning escalation thresholds are set from measurements (about 146–292 GB/year at 730M rows before bloat, WAL and replicas).
- **Measurement rules.**
  - The U41 baseline runs before every dependent gate, and calibrated per-fixture budgets are frozen before optimisation starts.
  - Latency is measured from request admission through commit and response encoding, failed attempts included; execution time is reported separately.
  - Count actual connector RPCs, not symmetric-function evaluations.
  - WAL is attributed on an otherwise quiet cluster, or LSN deltas are labelled as cluster totals.
  - Enough repetitions for p95 with an uncertainty estimate. EXPLAIN JSON is kept. Mutating EXPLAIN runs are rolled back, and commit-trigger cost is reported separately.

## 8. Clean Architecture compliance

Checked against `.cursor/rules/architecture.mdc` and the `clean-architecture` skill.

| Rule | Compliance | Existing divergence fixed |
|---|---|---|
| Domain is pure (no Flutter, `dart:ui`, Ferry, `data/` or `ui/`) | New domain code uses domain geometry records. Time, ids and delays are injected functions. Scheduling lives in UI. | `constellation_layout.dart:2` and `radial_hop_positions.dart:3` (`dart:ui`), `constellation_anchor_composition.dart:2` (`NodeDetails`). Purified via `layout_geometry.dart`, with UI adapters in the scene controller. |
| Entities and DTOs are Freezed; cases extend `UseCaseBase` | All new entities, states and port DTOs are Freezed. Both new cases extend `UseCaseBase`. | The client port DTOs are plain classes today (`constellation_anchor_repository_port.dart:3,13`). Converted. |
| Cubits use use cases, never repositories or services when orchestrating | The chrome cubit injects only cases | C:719 and C:2268 (`ForwardRepository`), the `ConstellationMemberWebsPort` injection. Moved behind `ForwardCase` and `ConstellationMemberWebsCase`. |
| Ferry stays in `data/` | Mappers in `data/model/` | — |
| Cubit state immutable | Freezed states with fresh collections. Scene and interaction controllers are not cubit state. | C's private mutable sets move into the interaction controller. |
| Server domain → ports only | `ConstellationAnchorCase.apply` → `ConstellationAnchorRepositoryPort.applyBatch` | — |
| DI | Application-lifetime `@singleton` cases with account-scoped contents, driven by `ConstellationAccountPort`. Clock, id and wake-up ports bound through Injectable adapters. Screen-owned controllers created and disposed by the screen. Repositories `@lazySingleton` env-scoped; mocks `env: [test], order: 1`; `build_runner` regenerates `di.config.dart`. | The cubit's optional `now` parameter (C:134) is replaced by `ClockPort` |
| Server perf mechanisms placed by layer | Per-(viewer, params) single-flight lives in the server domain use case `ConstellationFieldCase` (pure Dart). The worker-wide admission scheduler (priority, fairness, deadlines) is a data-layer service `data/service/constellation_db_scheduler.dart` behind a domain port `ConstellationDbAdmissionPort`; repositories enter transactions only through it. Limits come from `Env`. Dirty-generation coalescing and batched broadcast live in the API/websocket layer (`api/controllers/websocket/**`). Prepare-before-lock and tx-local reuse stay inside the data repository. Perf recording is test-only (`test/perf/`). | — |
| Generic package stays generic | No Tentura imports in `force_directed_graphview` | — |

**Suggested rule update** (the owner decides): `architecture.mdc` describes `domain/port/` for the server only, but client features (constellation, others) already use client-side ports. Suggest documenting the client usage.

## 9. Invariant → test map

All tests are structural; there are no goldens. Suites run serially through `scripts/run_with_test_cleanup.sh`, and custom lints are checked for both packages.

| Invariant / rule | Test (layer) |
|---|---|
| I1 | Package: node pointer claimed with zero camera movement during a node drag; taps, pinch and added pointers per policy. Widget: drag B while A is in flight. |
| I2 | Widget: store plus outbox emissions and a running transition during a drag → no committed node moves until release; then one compose, one plan, one transition. Cancel, lost capture and tab hidden each release exactly once. Resize mid-drag continues. |
| I3 | Domain property test: random diffs not touching X → X unchanged. Domain: a refresh missing a row doesn't remove a slot. Widget: failure → node stays with marker; Discard → animates to confirmed. |
| I4 | Profile web benchmark N = 100/300/600: drag frame, pan frame, longest task across drop→ack→reflow. Domain: AIMD convergence with a step change in unit cost; the scheduler never exceeds one slice per frame. |
| I5 | Domain: `place` → one `apply`, zero ANCHORS fetches; the ack causes no desired-state change. |
| I6 | Domain: cluster → one request; echo ≤ covered → no fetch; covered + 1 uncovered → one resync; hints buffered during in-flight. |
| R1 | Domain: A→B on one target with A ok / rejected / timeout → B's slot and position untouched. |
| R2 | Domain: queue over 64 ops → batches cut at cluster boundaries; maximum cluster; overlapping clusters with last-writer-wins. |
| R4/R7/R9 | Server pg: replaying the same op id → recorded result, no revision bump; same id with a different fingerprint → reject; `ifRevision` mismatch → `REJECTED(conflict)`. Domain: Discard on `commitUnknown` → resolve, then compensate or drop. |
| §5.3 F5 | Domain: concurrent foreign write before A → A's complete projection includes it, no resync; after A → uncovered hint → one resync; no lost row in either order. |
| §7.1 | Server pg: `anchorProjection` equals a fresh ANCHORS read at `afterRevision`; mixed accept/reject; a DB error rolls back all. |
| §7.2 | Server pg: one delivered hint per committed batch (mixed ops, absent delete, cascade) carrying the commit revision; rollback delivers none. Client: WS revision decoded, highest kept. |
| R1 promotion | Domain: successor dispatch after predecessor ok / rejected / unknown-resolved; an exhausted unknown blocks only its target; Retry of a rejected op uses a new id. |
| R7 compensation | Server pg: watermark survives delete; `ifRevision` mismatch → conflict. Domain: Discard on unknown → replay → compensate or drop; a dispatched compensation settles before its successor. |
| R8 lifetime | Domain: logout with zero leases clears the outbox, timers and subscriptions; no old-account request is sent after the generation changes. |
| §5.3 params | Domain: a result for obsolete params settles ids but doesn't replace anchors; FULL ordering is by read sequence, not anchor revision. |
| §5.4 freeze | Package: freeze between layout acceptance and its queued callback → no publication; pause/resume keeps destinations. |
| §7.3 | Server pg: trust/MR publication emits a global field hint; block emits to both parties. Client: global hint is spaced and jittered. Server: dirty-generation coalescing broadcasts at most once per window; admission returns `RETRY_LATER` over the limit; same-(viewer, params) FULLs share one computation. |
| §7.5–7.6 | Tagged server perf fixtures (V = 100/300/1000, sparse and dense trust, C = 100/1k/10k candidates, A = 0/20/200, batches of 1/16/64; reciprocal and fallback-score populations; cold and warm runs; real MR latency). Budgets per §7.6. MR RPC count per apply = 1 + U per context. Deferred callbacks call the publisher once per viewer per tx. Load test of publication and reconnect bursts. |

## 10. Risks

- **Large refactor and ordering.** The order is:
  1. mechanical purity and use-case splits behind the current public cubit API;
  2. server protocol: migration registration, projection reader, notifications and fan-out;
  3. schema refresh and mappers;
  4. codegen (Freezed, Ferry, Injectable, l10n);
  5. store and outbox semantics;
  6. gesture and render (D3).
  The old mutations are removed only in the release that ships the matching client semver, web cache-buster and `kDefaultMinClientVersion` together.
- **Long-lived `commitUnknown`.** Bounded by idempotent replay. The marker keeps it visible.
- **Deferred trigger semantics.** The NOTIFY fires at commit, after the tx's writes. pg tests pin the delivered payload, and the realtime fan-out code is unchanged apart from the extra field.
- **Idle-task starvation on web.** Handled by the independent wake-up plus job token (§5.6).
- **MR walks-cache sizing** (run 4). With `MERITRANK_WALKS_CACHE_SIZE` below the largest visible set, dense viewers pay about 6 s per read. Keep the cache ≥ largest visible set + 1, within the host memory budget. The connector deadline must stay above the **cold** first-read cost (about 2.4 s at V ≈ 1,000) or visibility fails closed for exactly the heaviest users on their first read.
- **Purity refactor of layout and composition** touches tested code. Do it as a mechanical type swap first (adapters at the boundary), with the existing tests as the oracle.
