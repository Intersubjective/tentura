# Future architecture improvements

This document records **architecture and engineering review outcomes** for the beacon **evaluation** feature (client + server), plus a **phased plan** for more robust long-term design. It is not a commitment schedule; prioritize by product need.

Related product docs: `beacon-evaluation-feature-design.md`, `beacon-evaluation-principles.md`.

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
