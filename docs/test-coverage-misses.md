# Test coverage misses — agent coordination index

**Purpose:** Actionable backlog of business-logic and contract tests that are missing or thin. Agents should claim items by ID, set `status: in_progress` in their PR description, and check off acceptance criteria.

**Branch baseline:** `main` (2026-06-25). Re-verify paths after large refactors.

**Verify locally (package under test):**

```bash
# Server unit tests (CI excludes pg-tagged)
cd packages/server && dart test --exclude-tags pg path/to/test.dart

# Server pg-tagged integration
cd packages/server && dart test --tags pg path/to/test.dart

# Client
cd packages/client && flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env path/to/test.dart

# Coverage (optional)
cd packages/server && dart test --exclude-tags pg --coverage=coverage
cd packages/client && flutter test --dart-define=ENV=test --dart-define-from-file=env/test.env --coverage
```

**Conventions for new tests:**

- Server use cases: mock **ports** (`domain/port/*`), not `data/repository/*`. Follow `packages/server/test/domain/use_case/invitation_case_test.dart` and `help_offer_case_test.dart`.
- Pure domain rules: test without DI; place under `packages/server/test/domain/` or `test/domain/` (root shared) or `packages/client/test/domain/`.
- Tag DB integration tests `@Tags(['pg'])` — CI skips them unless run explicitly.
- Do **not** commit generated files (`*.g.dart`, mocks may be committed if repo already does — follow sibling tests).

**Priority key:**

| Priority | Meaning |
|----------|---------|
| **P0** | Core product invariant; regression would cause user-visible wrong behavior or data corruption |
| **P1** | Important business rule; partial coverage or only tested indirectly |
| **P2** | Secondary flow, admin, or presentation derivation |
| **P3** | Nice-to-have, thin wrapper, or already covered at adjacent layer |

**Status key:** `open` · `in_progress` · `done` (agent sets in PR)

---

## 1. Shared root domain contracts

### COV-001 — Exhaustive beacon status transition table

| Field | Value |
|-------|-------|
| **Priority** | P0 |
| **Status** | done |
| **Source** | `lib/domain/entity/beacon_status_transition.dart` — `_allowedTransitions` (27 pairs) |
| **Existing** | `test/domain/entity/beacon_status_transition_test.dart` — **4** explicit transitions + smallint checks |
| **Gap** | Single source of truth for persisted status changes is not contract-tested. Server `CoordinationCase`, `BeaconCase`, `EvaluationCase` call `validateBeaconStatusTransition` but do not prove the full matrix. |
| **Recommended test** | Table-driven unit test: every allowed pair → `allowed`; representative forbidden pairs (e.g. `closed → open`, `draft → closed`) → `disallowed`; all `from == to` → `noop`. |
| **Acceptance** | 27/27 allowed pairs covered; ≥8 forbidden pairs; test lives in `test/domain/entity/beacon_status_transition_test.dart` or new `beacon_status_transition_matrix_test.dart`. |
| **Blast radius** | Server close/reopen/coordination intent, client status menus |

### COV-002 — `coordinationTargetStatus` mapping

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Status** | done |
| **Source** | `lib/domain/entity/beacon_status_transition.dart` — `coordinationTargetStatus` |
| **Existing** | None dedicated |
| **Gap** | Maps coordination smallints (2,3,7,8,…) to `BeaconStatus`; used when author sets coordination intent. |
| **Recommended test** | Unit tests for each smallint branch + default. |
| **Acceptance** | All branches in `switch` covered. |

### COV-003 — `reasonStringForTransition` round-trip sanity

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `lib/domain/entity/beacon_status_transition.dart` — `reasonStringForTransition` |
| **Existing** | Indirect via server use-case tests using reason strings |
| **Gap** | No test that every `BeaconStatusTransitionReason` enum value maps to a non-empty stable string. |
| **Recommended test** | Exhaustive enum test. |

---

## 2. Forwarding, involvement, dedup

### COV-010 — `ForwardEdgeRepository.createBatch` per-sender dedup

| Field | Value |
|-------|-------|
| **Priority** | P0 |
| **Status** | done |
| **Source** | `packages/server/lib/data/repository/forward_edge_repository.dart` — `createBatch` skips when `findActiveEdge` exists |
| **DB contract** | `packages/server/lib/data/database/migration/m0100.dart` — partial unique index `(beacon_id, sender_id, recipient_id) WHERE cancelled_at IS NULL` |
| **Existing** | `m0100_dedup_test.dart` — **string inspection only**; `forward_case_test.dart` — mock returns `[]` inserted (no repo behavior) |
| **Gap** | Invariant “same sender cannot create a second active edge to same recipient” is not executed against DB or repository. |
| **Recommended test** | `@Tags(['pg'])` integration: insert edge, call `createBatch` again with same triple, assert returned list excludes duplicate and DB has one active row. |
| **Acceptance** | Second forward skipped; first edge unchanged; optional third-party sender to same recipient still allowed. |
| **Refs** | Per-sender dedup invariant (partial unique index `m0100`) |

### COV-011 — `BeaconInvolvementCase` aggregation

| Field | Value |
|-------|-------|
| **Priority** | P0 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/beacon_involvement_case.dart` |
| **Existing** | None |
| **Gap** | V2 `beaconInvolvement` query aggregates forward/help/inbox rejection data including **`myForwardedRecipients`** for client dedup UX. |
| **Recommended test** | Unit test with mocked ports: verify mapping of edges/offers/rejections into `BeaconInvolvementResult`; auth failure via `BeaconAccessGuard`; `myForwardedRecipients` filtered to current sender. |
| **Acceptance** | ≥6 scenarios: author vs recipient view, forwarded-by-me list, rejected ids, empty graph, guard deny. |

### COV-012 — Client `ForwardCase.computeInvolvement` priority order

| Field | Value |
|-------|-------|
| **Priority** | P0 |
| **Status** | done |
| **Source** | `packages/client/lib/features/forward/domain/use_case/forward_case.dart` — `computeInvolvement` static method |
| **Existing** | `forward_state_scope_test.dart` — uses pre-built `ForwardCandidate`, not involvement merge |
| **Gap** | Priority order (`author` > `helpOffered` > `withdrawn` > **`forwardedByMe`** > `declined` > `forwarded` > …) untested. Regression would break per-sender dedup UI. |
| **Recommended test** | Pure unit test in `packages/client/test/features/forward/forward_compute_involvement_test.dart` with minimal `BeaconInvolvementData` fixtures. |
| **Acceptance** | One test per involvement type; **overlap tests** where user appears in both `myForwardedRecipientNotes` and `forwardedToIds` → `forwardedByMe` wins. |

### COV-013 — `BeaconForwardGraphCase` edge set + access

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/beacon_forward_graph_case.dart` |
| **Existing** | None for this use case; `beacon_help_offerer_forward_path_case_test.dart` covers a related path |
| **Gap** | V2 `beaconForwardGraph` visibility rules (author vs involved vs denied) not unit-tested. |
| **Recommended test** | Mock repos + `FakeBeaconAccessGuard`; assert edge filtering and exception on unauthorized viewer. |

### COV-014 — `ForwardCase` orchestration beyond reasons/push

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/forward_case.dart` — parent edge, inbox watching, access guard paths |
| **Existing** | `forward_case_test.dart`, `forward_case_auth_test.dart` |
| **Gap** | `updateForward` eligibility (read/forwarded/help offer), `parentEdgeId` lineage wiring, guard failures with specific exception codes. |
| **Recommended test** | Extend `forward_case_test.dart` groups. |

### COV-015 — Client forward repository → involvement merge integration

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/client/lib/features/forward/data/repository/forward_repository.dart` (maps GraphQL → candidates) |
| **Existing** | `forward_beacon_page_test.dart` — widget smoke with mocks |
| **Gap** | No test that GraphQL involvement payload produces correct `CandidateInvolvement` + note on candidate. |
| **Recommended test** | Unit test with fixture JSON / extension type wrapper (data layer only). |

---

## 3. Beacon lifecycle & status (server use cases)

### COV-020 — `BeaconCase.deleteBeacon` transition + committer guard

| Field | Value |
|-------|-------|
| **Priority** | P0 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/beacon_case.dart` — delete path uses `validateBeaconStatusTransition` + `everHadAcknowledgedCommitter` |
| **Existing** | `beacon_case_publish_draft_test.dart`, `beacon_create_rate_limit_test.dart` only |
| **Gap** | Delete rules untested at use-case level. |
| **Recommended test** | Mock `BeaconRepositoryPort` + coordination repo; scenarios: draft hard-delete, open→deleted allowed, blocked when committer existed, disallowed transition throws. |

### COV-021 — `BeaconCase` cancel / close orchestration

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/beacon_case.dart` — cancel/close entry points (if distinct from `EvaluationCase`) |
| **Existing** | Close/review heavily tested in `evaluation_case_test.dart`; cancel may be thin |
| **Gap** | Map each public `BeaconCase` mutation to tests; fill holes not covered by `EvaluationCase` / `CoordinationCase`. |
| **Recommended test** | Audit `beacon_case.dart` public API → list untested methods in PR; add focused tests per method. |
| **Acceptance** | Every `BeaconCase` public method has ≥1 happy + ≥1 deny test OR documented delegate to another case with cross-reference in this doc. |

### COV-022 — `CoordinationCase.setBeaconStatus` full matrix

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/coordination_case.dart` |
| **Existing** | `coordination_case_revert_test.dart` — **`needsMoreHelp`** focus from `reviewOpen`/`open` |
| **Gap** | `enoughHelp`, `neutralOpen`, transitions from `needsMoreHelp`/`enoughHelp` to `reviewOpen`/`closed`, steward vs author matrix incomplete. |
| **Recommended test** | Extend revert test file or add `coordination_case_status_test.dart`. |

### COV-023 — `BeaconDisplayCase` / server display derivation

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/beacon_display_case.dart` |
| **Existing** | `derive_beacon_display_status_test.dart` tests **pure** `deriveBeaconDisplayStatus`, not the case wrapper |
| **Gap** | Use-case wiring (inputs from repos, tier selection) untested. |
| **Recommended test** | Thin use-case test with mocks OR document as covered by pure function (if case is pass-through). |

---

## 4. Coordination items (promises, asks, blockers, plans)

**Subsystem:** `packages/server/lib/domain/use_case/coordination_item/*.dart` (~35 use cases).  
**Existing tests:** `accept_promise`, `create_promise`, `draft_blocker` (create/publish/delete), `update_plan`, `update_coordination_item`, `remind`, `coordination_responsibility`.

### COV-030 — Ask lifecycle (create → publish → mark → resolve → cancel)

| Field | Value |
|-------|-------|
| **Priority** | P0 |
| **Status** | done |
| **Sources** | `create_draft_ask_case.dart`, `publish_draft_ask_case.dart`, `update_draft_ask_case.dart`, `delete_draft_ask_case.dart`, `mark_ask_case.dart`, `accept_ask_case.dart`, `resolve_ask_case.dart`, `cancel_ask_case.dart`, `redirect_ask_case.dart` |
| **Existing** | `ask_lifecycle_case_test.dart` (all nine ask cases) |
| **Recommended test** | One test file per case or grouped `ask_lifecycle_case_test.dart` following `draft_blocker_case_test.dart` patterns (mock `CoordinationItemRepositoryPort`, room access). |
| **Acceptance** | Each case: happy path, unauthorized user, wrong item state, draft vs published guards. |

### COV-031 — Promise lifecycle (cancel, resolve, redirect, draft update)

| Field | Value |
|-------|-------|
| **Priority** | P0 |
| **Status** | done |
| **Sources** | `cancel_promise_case.dart`, `resolve_promise_case.dart`, `redirect_promise_case.dart`, `create_draft_promise_case.dart`, `publish_draft_promise_case.dart`, `update_draft_promise_case.dart`, `delete_draft_promise_case.dart` |
| **Existing** | `create_promise_case_test.dart`, `accept_promise_case_test.dart` only |
| **Gap** | Cancel/resolve/redirect and draft promise flows untested. |

### COV-032 — Blocker lifecycle (mark, resolve, cancel)

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Status** | done |
| **Sources** | `mark_blocker_case.dart`, `resolve_blocker_case.dart`, `cancel_blocker_case.dart`, `update_draft_blocker_case.dart` |
| **Existing** | Draft create/publish/delete blocker tested |
| **Gap** | Operational resolve/cancel/mark untested. |

### COV-033 — Resolution lifecycle

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Status** | done |
| **Sources** | `create_resolution_case.dart`, `accept_resolution_case.dart`, `reject_resolution_case.dart` |
| **Existing** | None |

### COV-034 — Plan step lifecycle

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Status** | done |
| **Sources** | `add_plan_step_case.dart`, `resolve_plan_step_case.dart` |
| **Existing** | `update_plan_case_test.dart` only |
| **Gap** | Add step and resolve step untested. |

### COV-035 — `coordination_room_access.dart` shared guard

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/coordination_item/coordination_room_access.dart` |
| **Existing** | Exercised indirectly in some case tests |
| **Gap** | No dedicated tests for room admission rules used by multiple cases. |
| **Recommended test** | Pure/unit tests for access helper functions before duplicating setup across 20 case files. |

### COV-036 — Client `CoordinationItemCase`

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Status** | done |
| **Source** | `packages/client/lib/features/coordination_item/domain/use_case/coordination_item_case.dart` |
| **Existing** | Entity tests (`coordination_item_stale_test`, `coordination_item_involvement_test`); widget tests for room tiles |
| **Gap** | Client orchestration (load, mutate, stream refresh) untested. |
| **Recommended test** | Unit tests with mocked repository port; mirror server scenarios at UI boundary. |

---

## 5. Evaluation & post-close

### COV-040 — `EvaluationCase.beaconClose` full scenarios

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/evaluation_case.dart` |
| **Existing** | `evaluation_case_test.dart` — `beaconClose review cycle reset` group (limited) |
| **Gap** | Direct close vs review-open path, author close now, review expired, insufficient participants. |
| **Recommended test** | Extend evaluation_case_test groups; use existing fakes in `evaluation_graph_test_repos.dart`. |

### COV-041 — Client `EvaluationCase`

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/client/lib/features/evaluation/domain/use_case/evaluation_case.dart` |
| **Existing** | `evaluation_case_test.dart` (repository delegation for all public methods) |
| **Gap** | Case is a thin repository facade; no client-specific orchestration beyond delegation. |

---

## 6. Beacon rooms & messaging

### COV-050 — `BeaconRoomCase` send / edit / delete message flows

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/beacon_room_case.dart` |
| **Existing** | mark-seen, plan thread, attachment quota, last-activity batch |
| **Gap** | Core message mutation paths may lack direct tests — audit public methods. |
| **Recommended test** | Per-method unit tests with mocked `BeaconRoomRepositoryPort`. |

### COV-051 — Room admission edge cases beyond help offer

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Status** | done |
| **Source** | `help_offer_case_test.dart` auto-admit group; `coordination_item` room access |
| **Gap** | Steward admit, revoke, re-admit paths scattered; no consolidated admission matrix. |

### COV-052 — Client `BeaconRoomCase` + optimistic sends

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/client/lib/features/beacon_room/domain/use_case/beacon_room_case.dart` |
| **Existing** | `room_cubit_unread_test`, reaction local tests, layout goldens |
| **Gap** | Use-case-level tests for pending upload / send retry policy if present in case. |

---

## 7. Access & visibility

### COV-060 — `BeaconAccessGuard` matrix (if logic exceeds visibility pure functions)

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/port/beacon_access_guard.dart` + implementation in data layer |
| **Existing** | `beacon_visibility_test.dart` (pure facts); `FakeBeaconAccessGuard` in use-case tests |
| **Gap** | Real guard implementation integration with roles/edges may differ from pure visibility. |
| **Recommended test** | Unit/integration tests on concrete guard class if non-trivial; else document equivalence to `beacon_visibility.dart`. |

### COV-061 — `beacon_access_sql_parity` expansion

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/server/test/data/repository/beacon_access_sql_parity_test.dart` |
| **Existing** | pg-tagged parity tests (partial) |
| **Gap** | New roles or V2 paths may be missing — extend when adding GraphQL fields. |

---

## 8. Auth, session, credentials (residual gaps)

### COV-070 — `UserCase` business rules

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/user_case.dart` |
| **Existing** | `account_profile_controller_test.dart` (HTTP layer) |
| **Gap** | Use-case-level profile update rules, handle validation, privacy fields. |

### COV-071 — Client `CredentialsCase`

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/client/lib/features/credentials/domain/use_case/credentials_case.dart` |
| **Existing** | `credentials_repository_test.dart`, `credentials_test.dart` (partial) |
| **Gap** | Case orchestration not isolated. |

### COV-072 — `UnsubscribeCase.apply` / `peek`

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/unsubscribe_case.dart` |
| **Existing** | `unsubscribe_token_test.dart` — token crypto only |
| **Gap** | apply/peek orchestration with preference repo (all vs category scope) untested. |

---

## 9. Notifications

### COV-080 — `NotificationPreferenceCase.update` validation

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/notification_preference_case.dart` |
| **Existing** | `notification_preference_gate_test.dart` — gate logic related, not case |
| **Gap** | Category parsing, quiet hours, snooze, invalid category strings. |
| **Recommended test** | Unit test with mock `NotificationPreferenceRepositoryPort`. |

### COV-081 — `NotificationCenterCase`

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/notification_center_case.dart` |
| **Existing** | Client `notification_center_cubit_test.dart` |
| **Gap** | Server use case untested (pagination, mark read, fan-in rules). |

### COV-082 — `BeaconNotificationService` dedup + outbox

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/server/lib/data/service/beacon_notification_service.dart` |
| **Existing** | Domain tests for copy/recipient resolver; `email_notification_service_test.dart` |
| **Gap** | `_dedupKey` collision behavior, unread collapse — service-level unit tests. |

### COV-083 — Client FCM / notification preference sync

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/client/lib/features/notification/domain/use_case/fcm_case.dart` |
| **Existing** | `fcm_case_test.dart` (server); client `notification_settings_cubit_test.dart` |
| **Gap** | Client `FcmCase` token lifecycle if distinct from server. |

---

## 10. Inbox & My Work

### COV-090 — Server inbox repository / watching provenance

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Status** | done |
| **Source** | `InboxRepositoryPort` implementations; forward → watching in `ForwardCase` |
| **Existing** | Mocked in `forward_case_test`; `m0100` provenance SQL string test |
| **Gap** | Inbox state machine (watching, rejected, read) not unit-tested at repo level. |

### COV-091 — Client `InboxCase`

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/client/lib/features/inbox/domain/use_case/inbox_case.dart` |
| **Existing** | `inbox_item_status_test.dart` (presentation) |
| **Gap** | Case orchestration untested. |

### COV-092 — Client `MyWorkCase` stream merge / invalidation

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/client/lib/features/my_work/domain/use_case/my_work_case.dart` |
| **Existing** | Strong derivation tests; `my_work_case_load_desk_test.dart` |
| **Gap** | Multi-stream debounce / cache invalidation paths in case. |

---

## 11. Trust, MeritRank, graph

### COV-100 — `MeritrankCase`

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/meritrank_case.dart` |
| **Existing** | None |
| **Gap** | Admin init/calculate privilege gates untested. |

### COV-101 — `UserTrustEdgeCase`

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/user_trust_edge_case.dart` |
| **Existing** | `trust_math_test.dart` (bins + optional SQL) |
| **Gap** | Use-case orchestration for creating/removing trust edges. |

### COV-102 — Client graph path pruning / forward graph UI rules

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/client/test/features/graph/prune_directed_paths_test.dart` |
| **Gap** | Broader graph layout rules and MeritRank sort keys in UI untested. |

### COV-103 — `MutualFriendsCase`

| Field | Value |
|-------|-------|
| **Priority** | P3 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/mutual_friends_case.dart` |
| **Existing** | None |

---

## 12. Lineage & fork beacons

### COV-110 — `BeaconLineageSuggestionsCase` policy expansion

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/beacon_lineage_suggestions_case.dart` |
| **Existing** | 3 tests in `beacon_lineage_suggestions_case_test.dart` |
| **Gap** | Pushback thresholds, de-prioritize/suppress, G2/G4 groups, non-fork empty — see `docs/adr/0004-beacon-lineage-fork.md`. |
| **Recommended test** | Table-driven cases from ADR examples. |

### COV-111 — `BeaconFactCardCase`

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/beacon_fact_card_case.dart` |
| **Existing** | `beacon_fact_card_consts_test.dart` |
| **Gap** | CRUD visibility rules at use-case level. |

---

## 13. Capabilities

### COV-120 — `fetchDeduplicatedCapabilities` semantics

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/server/lib/data/repository/person_capability_event_repository.dart` |
| **Existing** | Close-ack dedup pg test; `capability_case_test.dart` |
| **Gap** | Dedup SQL for viewer-visible slugs not isolated. |

### COV-121 — Client capability batch fetch / cue derivation

| Field | Value |
|-------|-------|
| **Priority** | P3 |
| **Status** | done |
| **Source** | `packages/client/lib/domain/capability/person_capability_cues.dart` |
| **Existing** | Minimal |
| **Gap** | Cue grouping rules untested. |

---

## 14. Contacts & private names

### COV-130 — Client `ContactsCase`

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/client/lib/features/contacts/domain/use_case/contacts_case.dart` |
| **Existing** | Server `contact_case_test.dart`, `contact_linking_policy_test.dart` |
| **Gap** | Client overlay merge (`ContactNameStore`) untested at case level. |

---

## 15. Polling, complaints, presence, workers

### COV-140 — `PollingCase` (server)

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/polling_case.dart` |
| **Existing** | None |

### COV-141 — Client `PollingCase`

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/client/lib/features/polling/domain/use_case/polling_case.dart` |
| **Existing** | None |

### COV-142 — `ComplaintCase`

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/complaint_case.dart` |
| **Existing** | None |

### COV-143 — `UserPresenceCase`

| Field | Value |
|-------|-------|
| **Priority** | P3 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/user_presence_case.dart` |
| **Existing** | None |

### COV-144 — `TaskWorkerCase`

| Field | Value |
|-------|-------|
| **Priority** | P3 |
| **Status** | done |
| **Source** | `packages/server/lib/domain/use_case/task_worker_case.dart` |
| **Existing** | None |
| **Note** | May be better suited to integration/smoke tests than unit. |

---

## 16. Client infrastructure & cross-cutting

### COV-150 — `InvalidationService` debounce + dedup

| Field | Value |
|-------|-------|
| **Priority** | P0 |
| **Status** | done |
| **Source** | `packages/client/lib/data/service/invalidation_service.dart` |
| **Existing** | None; behavior documented in `DEV_GUIDELINES.md` |
| **Gap** | `bufferTime` window merges duplicate `(entityType, id)` pairs; echo suppression depends on server + client pairing. |
| **Recommended test** | Unit test with fake clock / streamed events; assert single repo refresh per window. |
| **Acceptance** | Burst of identical invalidations → one emitted batch; different ids in same window → both kept. |

### COV-151 — Client `BeaconViewCase` orchestration

| Field | Value |
|-------|-------|
| **Priority** | P1 |
| **Status** | done |
| **Source** | `packages/client/lib/features/beacon_view/domain/use_case/beacon_view_case.dart` |
| **Existing** | Many **derivation** tests (chips, closure, people tab); cubit tests partial |
| **Gap** | Case-level stream wiring (invalidation → refetch, forward completed) untested without full cubit. |

### COV-152 — Auth loss classifier / session repository edge cases

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/client/lib/data/service/auth_loss_classifier.dart` |
| **Existing** | `auth_loss_classifier_test.dart` |
| **Gap** | Re-audit for new GraphQL error shapes when added. |

---

## 17. Repository & integration gaps (data layer)

### COV-160 — `forward_edge_repository` beyond createBatch

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `forward_edge_repository.dart` — `fetchHelpOffererPathChain`, cancel edge |
| **Existing** | Path chain tested via `beacon_help_offerer_forward_path_case` with mocks, not repo |
| **Recommended test** | pg-tagged SQL tests for recursive CTE shapes. |

### COV-161 — `coordination_responsibility_repository` aggregation

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `packages/server/test/data/repository/coordination_responsibility_repository_test.dart` |
| **Existing** | Some pg tests |
| **Gap** | Audit counts vs product spec when responsibility model changes. |

### COV-162 — Email auth transaction repository

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | `email_auth_transaction_repository_test.dart` |
| **Note** | Exists; keep updated when auth flows change — link from auth PRs. |

---

## 18. CI & coverage meta

### COV-170 — No CI coverage collection

| Field | Value |
|-------|-------|
| **Priority** | P3 |
| **Status** | done |
| **Source** | `.github/workflows/pipeline.yml` — `flutter test` / `dart test` without `--coverage` |
| **Gap** | No trend tracking or `fail-under` threshold. |
| **Recommended** | Optional CI job uploading lcov; exclude generated paths per hand-written-only metric in this doc's baseline (~47% server domain, ~24% client features hand-written). |

### COV-171 — pg-tagged tests not in CI

| Field | Value |
|-------|-------|
| **Priority** | P2 |
| **Status** | done |
| **Source** | CI: `dart test --exclude-tags pg` |
| **Gap** | Repository parity tests only run locally/with Postgres. |
| **Recommended** | Document in PR template; run locally with compose Postgres. |

---

## 19. Already well covered (do not duplicate)

Agents should **extend** these files rather than rewrite parallel suites:

| Area | Primary tests |
|------|----------------|
| Invites | `packages/server/test/domain/use_case/invitation_case_test.dart`, client `features/invitation/*_test.dart` |
| Help offers + auto-admit | `packages/server/test/domain/use_case/help_offer_case_test.dart` |
| Evaluation graph & visibility | `packages/server/test/domain/evaluation/*` |
| Beacon visibility matrix | `packages/server/test/domain/beacon_visibility_test.dart` |
| Auth / session / OIDC / email auth | `packages/server/test/domain/use_case/{auth,session,oidc,email_auth,credential_auth}_case_test.dart` |
| Coordination phase (client) | `packages/client/test/domain/coordination/derive_beacon_coordination_phase_test.dart` |
| Close readiness (client) | `packages/client/test/features/beacon_view/beacon_closure_readiness_test.dart` |
| My Work card derivation | `packages/client/test/features/my_work/derive_my_work_cards*_test.dart` |
| Notification copy/gates | `packages/server/test/domain/notification/*` |
| Read watermarks | `packages/client/test/features/beacon_room/room_read_watermark_store_test.dart` |

---

## 20. Suggested agent work packages

Split work to reduce merge conflicts:

| Package | IDs | Est. focus |
|---------|-----|------------|
| **A — Contracts** | COV-001, COV-002, COV-010, COV-012 | Root domain + forward dedup |
| **B — Forward server** | COV-011, COV-013, COV-014, COV-015 | Involvement + graph |
| **C — Beacon lifecycle** | COV-020, COV-021, COV-022 | Server beacon/coordination status |
| **D — Coordination items** | COV-030 – COV-036 | Largest batch (~20 case files) |
| **E — Rooms & inbox** | COV-050 – COV-052, COV-090, COV-091 | |
| **F — Notifications & email** | COV-072, COV-080 – COV-082 | |
| **G — Client infra** | COV-150, COV-151, COV-036, COV-091 | Invalidation + feature cases |
| **H — Trust / lineage / misc** | COV-100 – COV-103, COV-110, COV-140 – COV-144 | |

---

## Changelog

| Date | Change |
|------|--------|
| 2026-06-25 | Initial index from coverage audit on `main` |

| 2026-06-26 | Rollup: 52/52 COV items implemented; per-COV commits on main |
