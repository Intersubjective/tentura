# Future architecture improvements

This document records **architecture and engineering review outcomes** for the beacon **evaluation** feature (client + server) and for **overcommit coordination** (active `OPEN` beacons), plus **phased plans** for more robust long-term design. It is not a commitment schedule; prioritize by product need.

Related product docs: `beacon-evaluation-feature-design.md`, `beacon-evaluation-principles.md`.

**Overcommit coordination** is specified in `overcommit-coordination-feature-design.md`. It is separate from post-close **evaluation**: coordination rows are operational fit/coverage during `OPEN` beacons; evaluation is bounded to the review window after closure and must not be conflated in UX or reputation surfaces.

---

## Conformance (current implementation)

### Aligned with project guidelines

- **Layering:** `EvaluationCubit` → `EvaluationRepository` → feature domain entities. Ferry / GraphQL types stay in `data/`; mapping is centralized (e.g. `_participantFromGraphqlRow` in `packages/client/lib/features/evaluation/data/repository/evaluation_repository.dart`).
- **State:** `EvaluationState` uses Freezed + `StateBase`; initial async load uses loading state before painting success UI (see `DEV_GUIDELINES.md`).
- **DI:** `EvaluationRepository` is `@lazySingleton`; cubit receives the repository via constructor / `fromGetIt`.
- **V2 GraphQL:** Evaluation operations are routed via `_tenturaDirectOperationNames` in `packages/client/lib/data/service/remote_api_client/build_client.dart`.
- **Repository aggregates:** `fetchDraftModeBootstrap` loads review window info and draft participants in parallel with a typed record return, keeping the cubit free of `Future.wait` + casts.

### Acceptable flexibility

- **No client-side use cases** for evaluation yet: project rules allow BLoC/Cubit to use repositories directly. Introduce use cases when orchestration grows (offline, retries, analytics, etc.).

---

## Pressure points (technical debt / scale)

1. **Server `EvaluationCase` size** — Visibility graph and summary tone/suppression logic now live in **`evaluation_visibility_rules`** / **`evaluation_summary_rules`** (Phase A); orchestration, I/O, and GraphQL-shaped maps remain in the use case. Further splits (e.g. submit/finalize) are optional as rules grow.

2. **`reviewWindowStatus` payload vs. name** — The resolver still bundles beacon metadata (`beaconTitle`) and window/progress fields; `reviewedCount` now uses a **batched** evaluation read (Phase A). The **name** still does not spell out “full evaluation bootstrap”; rename/split remains a Phase B concern.

3. **N+1 pattern on evaluation rows** — **Addressed (Phase A):** `listEvaluationsForEvaluator(beaconId, evaluatorId)` batches rows; `reviewWindowStatus`, `evaluationParticipants`, and `evaluationDraftParticipants` use one query per call. Per-participant **`getById` for user profile** in participant list flows can still scale with visibility count if that becomes hot.

4. **Untyped `Map<String, dynamic>`** — Use case results are maps consumed by GraphQL. Typed DTOs in the domain layer, mapped at the resolver boundary, would improve refactors and IDE support.

   **Phase 1 (lints-first, shipped):** `no_map_dynamic_in_use_case_api` in `packages/tentura_lints` blocks new map-shaped public use-case APIs; existing server violations are baselined with `// TODO(contract): Phase-2 DTO migration — …` + `// ignore: no_map_dynamic_in_use_case_api` so Phase B refactors can remove them file-by-file. Related: `cubit_requires_use_case_for_multi_repos` + baselines for multi-repo cubits pending thin `*Case` orchestration.

5. **Server-side user-visible strings** — Summary messages (e.g. “No feedback”, privacy-limited copy) are English literals in **`evaluation_summary_rules.dart`** (Phase A moved them out of `EvaluationCase`). For multilingual UX, define whether copy is **client-localized from codes** or **server-rendered with locale**—then implement consistently (Phase C).

6. **Client loading granularity** — `submitOne` drives **full-screen** loading for the review screen. Acceptable today; consider per-row or overlay “saving” state if UX needs to keep the list visible during saves.

7. **Schema rollout** — Non-null additions (e.g. `beaconTitle` on `ReviewWindowStatus`) require **coordinated** server/client deploy or a short nullable transition if mixed versions must be supported.

---

## Phased improvement plan

### Phase A — Server structure and queries **(done)**

**Shipped:**

- **`EvaluationRepository.listEvaluationsForEvaluator`** — single query for all evaluation rows for `(beaconId, evaluatorId)`; used by `reviewWindowStatus`, `evaluationParticipants`, and `evaluationDraftParticipants` (no per-row `getEvaluation` in those paths).
- **`evaluation_visibility_rules.dart`** — `buildEvaluationVisibility` + types; tests: `test/domain/evaluation/evaluation_visibility_rules_test.dart`.
- **`evaluation_summary_rules.dart`** — tone, aggregates, suppression policy, role summary line, GraphQL-shaped `buildEvaluationSummaryGraphqlPayload`; tests: `test/domain/evaluation/evaluation_summary_rules_test.dart`.

**Original intent:** pure visibility + summary rules testable without Drift; batch evaluation reads for window/participant flows.

### Phase B — API clarity

- Decide: one **bootstrap** query vs. separate **beacon** + **window** queries. If one query remains, **rename or document** it explicitly (e.g. “evaluation context”) so SRP is intentional.
- Optionally introduce **typed result objects** for evaluation flows and map them in GraphQL resolvers instead of ad hoc maps.

### Phase C — Localization

- Choose strategy: **message codes + client ARB** vs. **server i18n** (e.g. locale-aware resolver). Remove hard-coded English from **`evaluation_summary_rules`** (and any remaining literals in the use case) in favor of that strategy.

### Phase D — Client (when complexity warrants)

- Add **evaluation use cases** to keep cubits thin if you add offline queues, retry policies, or cross-feature orchestration.
- Add **fine-grained loading state** (e.g. `savingEvaluatedUserId`) if product wants non-blocking list UI during submit.

### Phase E — Contract and deployment

- Document **ordering** for schema changes (server before client when adding required fields) or use **nullable defaults** during transition windows.

---

## Overcommit coordination — conformance (current implementation)

### Aligned with project guidelines

- **V2 GraphQL:** Coordination operations are listed in `_tenturaDirectOperationNames` (`packages/client/lib/data/service/remote_api_client/build_client.dart`).
- **Layering:** Client `BeaconViewCubit` → `CoordinationRepository` / `ForwardRepository` / `BeaconRepository`; Ferry types mapped in data (`UserModel.toEntity()`). Server `CoordinationCase` / `CommitmentCase` orchestrate repositories.
- **DI:** `@Singleton` use cases, `@lazySingleton` / `@Injectable` repositories per project conventions.
- **Domain validation:** `help_type` / `uncommit_reason` allowlists live under `packages/server/lib/domain/coordination/`.
- **Errors:** `CommitmentCoordinationException` with a dedicated code space fits hierarchical server exceptions.

### Acceptable flexibility

- **No client-side use cases** for coordination yet; introduce a thin use case if orchestration grows (retries, analytics, cross-feature flows) — same stance as evaluation (Phase D).

---

## Overcommit coordination — pressure points (technical debt / scale)

1. **Derivation logic location** — Beacon coordination status is derived inside `CoordinationRepository.recomputeAndPersistBeaconCoordinationStatus` (I/O-coupled). Unlike evaluation, there is **no** pure `coordination_status_rules` module with **unit tests** yet. Refactors and product tweaks (mixed responses, staleness nuance) are higher-risk without extraction.

2. **Spec §8.5 staleness vs implementation** — The spec describes staleness using **“commit without a response and created after `coordination_status_updated_at`.”** The shipped logic effectively treats **any active commitment missing a coordination row** as “waiting for review” and updates `coordination_status_updated_at` on recompute. Often stricter than §8.5; **not identical** if product later needs “all older commits answered, only new ones pending.” **Document** the chosen rule in `overcommit-coordination-feature-design.md` or **align** code once rules live in a pure function.

3. **`setBeaconCoordinationStatus` vs automatic recompute** — Manual author status updates do not run the same derivation pipeline as commit/withdraw; the **next** commit/withdraw **recomputes** and may **overwrite** the manual value. Behavior is **implicit** today; risks confusing UX (“I set Enough help and it changed”). **Decide** a product contract: advisory until next event, pinned override until new commits, or always derive — then document and, if needed, implement (e.g. pin flag or post-mutation recompute policy).

4. **Untyped `Map<String, dynamic>`** — `commitmentsWithCoordination` builds maps for GraphQL (same pattern as some evaluation payloads). **Typed DTOs or domain row types** at the use-case/resolver boundary would improve refactors and IDE support (same direction as evaluation Phase B).

5. **N+1 in `commitmentsWithCoordination`** — Per-row user (and related) loads scale poorly with many commitments on one beacon. **Batch or join** before this path becomes hot.

6. **Auditability / timeline (spec §17.3)** — Discrete timeline or audit events for coordination response changes and beacon-level coordination changes are **not** implemented; only existing commitment/withdraw timeline behavior. Harder debugging and weaker “later review context” unless **deferred explicitly** in the design doc.

7. **List surfaces: author response to the viewer’s commitment** — Beacon list tiles expose **beacon-level** coordination; **My Work**-style “author’s response to **this** user’s commit” (per spec) may need a **narrow field** or query to avoid over-fetching every row.

---

## Phased improvement plan — overcommit coordination

### Coordination Phase A — Pure rules and tests

- Extract a **`coordination_status_rules`** (or equivalent) module with a **pure** `deriveBeaconCoordinationStatus(...)` (inputs: active commitments, response map, timestamps as needed).
- Add **unit tests** mirroring `evaluation_visibility_rules_test.dart` / `evaluation_summary_rules_test.dart`.
- **Document** staleness behavior vs `overcommit-coordination-feature-design.md` §8.5; **optionally align** implementation to the spec predicate after rules are testable.

### Coordination Phase B — API shape and query efficiency

- Introduce **typed result objects** for `commitmentsWithCoordination` at the use-case or resolver boundary; map once to the GraphQL shape.
- **Batch or join** user (and image if applicable) loads for `commitmentsWithCoordination` to remove N+1.

### Coordination Phase C — Product contract and audit

- **Document** (in the design doc) or **implement** the chosen model for **manual** `setBeaconCoordinationStatus` vs **derived** status after commit/withdraw.
- Implement **§17.3** audit/timeline events (or record an explicit **Phase-1 deferral** in the design doc if out of scope).

### Coordination Phase D — Client completeness (when product requires)

- **My Work / list:** add a **minimal** way to show the author’s response to the **current viewer’s** commitment without heavy per-row payloads.
- Add **client use cases** if coordination orchestration grows (same trigger as evaluation Phase D).

---

## References (code)

| Area | Location |
|------|-----------|
| Client cubit | `packages/client/lib/features/evaluation/ui/bloc/evaluation_cubit.dart` |
| Client repository | `packages/client/lib/features/evaluation/data/repository/evaluation_repository.dart` |
| Server use case | `packages/server/lib/domain/use_case/evaluation_case.dart` |
| Evaluation visibility (pure) | `packages/server/lib/domain/evaluation/evaluation_visibility_rules.dart` |
| Evaluation summary / suppression (pure) | `packages/server/lib/domain/evaluation/evaluation_summary_rules.dart` |
| Server evaluation persistence | `packages/server/lib/data/repository/evaluation_repository.dart` (`listEvaluationsForEvaluator`, …) |
| V2 operation routing | `packages/client/lib/data/service/remote_api_client/build_client.dart` |
| Architecture rules | `.cursor/rules/architecture.mdc`, `.cursor/rules/quick-reference.mdc` |
| Screen load UX | `DEV_GUIDELINES.md` (initial load / spinner) |
| Coordination product spec | `docs/overcommit-coordination-feature-design.md` |
| Server coordination use case | `packages/server/lib/domain/use_case/coordination_case.dart` |
| Server coordination persistence / derivation | `packages/server/lib/data/repository/coordination_repository.dart` |
| Client coordination repository | `packages/client/lib/features/beacon_view/data/repository/coordination_repository.dart` |
| Beacon view orchestration | `packages/client/lib/features/beacon_view/ui/bloc/beacon_view_cubit.dart` |
