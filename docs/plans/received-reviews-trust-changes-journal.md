# Received Reviews & Trust-Change Visibility — Implementation Journal

**Objective:** Implement `docs/plans/received-reviews-trust-changes-plan.md` (issue #107) end to end.
**Plan source:** `docs/plans/received-reviews-trust-changes-plan.md` (rev 5, implementation-ready).
**Orchestration:** overseer skill, Cursor CLI workers (`composer-2.5`, one at a time, fresh session per unit).

## Repository state at start

- Repo: `/home/vader/MY_SRC/tentura`, branch `main`, starting HEAD `14e89bbf888f3c0c3b9dbc15f69341322546b68a` (ahead of origin/main by 4).
- Pre-existing uncommitted changes at start (NOT owned by this work — never commit, stash, or discard them):
  - Modified: `docs/README.md`, `docs/archive/journals/commitment-truth-rework-journal.md`, `docs/archive/plans/commitment-truth-rework-plan.md`, `docs/audits/room-coordination-audit.md`, `packages/client/web/index.html`, `packages/server/lib/data/database/table/beacon_commitment_events.dart`, `packages/server/lib/env.dart` (one-line doc-path comment fix — unrelated to `kDefaultMinClientVersion`, which this plan's Unit F1 will also touch; preserve the comment fix when editing that file).
  - Untracked: `dart-defines`, `docs/plans/graph-navigation-implementation-guide.md`, `docs/plans/graph-navigation-rework-plan.md`, `graph-ego-neighbors-layout-issue.md`, `key.fb`, `out.key`, `product_testing_compact_buglist.md`, `product_testing_detailed_report.md`. (`key.fb`/`out.key` look like key material — never read, commit, or touch.)
- None of the above overlap the plan's file-touch checklist (§10), so no conflict is expected, but re-check `git status` before every commit and only `git add` the specific files each unit owns.

## Verification commands (from AGENTS.md / plan §7)

```bash
cd packages/tentura_lints && dart test
./scripts/check-custom-lints.sh packages/client   # baseline: 111
./scripts/check-custom-lints.sh packages/server   # baseline: 0
cd packages/client && flutter test
cd packages/server && dart test                    # (confirm exact invocation; server test dir uses `-x pg` tag per memory for DB-gated tests)
```

Codegen (only after changing GraphQL/Freezed/Drift/AutoRoute/Injectable/`.arb`):
```bash
cd packages/client && flutter gen-l10n && dart run build_runner build -d
cd packages/server && dart run build_runner build -d
```

## Ordered work manifest

Derived from plan §8 "Rollout order," split into worker-sized units. Cursor workers run
strictly sequentially (one at a time), even where §8 says phases could parallelize.

| # | Unit | Plan sections | Status |
|---|------|----------------|--------|
| A1 | Server: `evaluationSummary` → `evaluationReceived` rework, drop `noBasis` filter, delete `countDistinctEvaluatorsForEvaluated` + callers/mocks/tests | §4.1 | done |
| A2 | Server: `listFinalizedEvaluationsBetween` port method + `CrossBeaconEvaluationRecord` + Drift impl + `evaluationsWrittenAboutMeBy` use case | §4.2 | done |
| A3 | Server: GraphQL API wiring (`query_evaluation.dart`, `custom_types.dart`, `gql_v2_dto_maps.dart`, `gql_public` DTOs) | §4.5 | done |
| B1 | Server: widen `closeAndFinalize` return + `ReviewCloseSnapshot.beaconTitle` + `AttentionIntentCase` builders + call sites (`EvaluationCase.closeNow`, `AttentionExpirySweepCase.runDue`) | §4.3 | done |
| B2 | Server+client: `AttentionEventType` + exhaustive `attention_policy.dart` switches + `AttentionDestinationKind.receivedReviews` + contract JSON (both copies) + `attention_policy_test.dart` fixtures + client `destination_map.dart` wire-name branch | §4.4 | done |
| C1 | Client: domain entity `evaluation_received.dart`, repository methods + `.graphql` docs, `schema.graphql` update, `build_client.dart` operation names, codegen | §5.1 | done |
| C2 | Client: `ReceivedReviewsScreen` + `ReceivedReviewTile` + route wiring (`root_router.dart`, `consts.dart`, `home_tab_branches.dart`) + `EvaluationSummaryCard` fix/replace | §6.3, §6.6 | done |
| C3 | Client: entry points — `ReviewWindowBannerHost`/`beacon_operational_header_card.dart` always-visible CTA + `ClosedRequestBanner` CTA | §6.4 | pending |
| D1 | Client: `TrustChangeReceiptCard` + presentation-key direction threading + `updates_receipt_display_copy.dart` + `updates_screen.dart` dispatch | §5.3, §6.2 | pending |
| E1 | Client: `ProfileReviewsAboutMeCubit` + `reviews_about_me_from_profile_sliver.dart` wiring into `profile_view_screen.dart` | §5.2, §6.5 | pending |
| F1 | Client: l10n keys (en+ru) + `pubspec.yaml` version bump + `MIN_CLIENT_VERSION` decision per `DEV_GUIDELINES.md` | §6.7, versioning rule | pending |
| F2 | Overseer-run: full plan-level verification sweep against §7 acceptance table, gap-fill any missing test coverage, close out | §7 | pending |

Dependencies: A1→A2 (repository file overlap), A2→A3 (needs new types), B1 depends on A1 (evaluation_case.dart churn) landing first to avoid merge pain, B2 depends on B1. C1 depends on A1-A3+B2 (GraphQL schema/contract must be stable before client codegen). C2/C3 depend on C1. D1 depends on B2+C1. E1 depends on A2+C1. F1 last (touches version files), F2 last of all.

**Correction (before either B unit was dispatched):** the above "B2 depends on B1" is
backwards and was caught by the overseer during B1 prompt-writing, before any worker ran.
§4.3's `AttentionIntentCase.trustGivenChanged`/`trustReceivedChanged` builders must
reference `AttentionEventType.trustGivenChanged`/`trustReceivedChanged`, which only
exist once §4.4 adds them to the enum — and the instant those enum values exist, every
no-fallback exhaustive switch in `attention_policy.dart` must gain matching cases or the
file fails to compile. §4.4 (enum + policy switches + `AttentionDestinationKind.receivedReviews`
+ contract JSON + `attention_policy_test.dart` fixtures + client `destination_map.dart`
branch) is self-contained and compiles/tests cleanly with no producer yet emitting the new
event types (the contract's `producer` field is just a documentation string). §4.3 (finalization
return widening + intent builders + call-site wiring) is the one with a real forward
dependency. **Actual dispatch order: B2 (§4.4) first, then B1 (§4.3) second** — the reverse of
the table above and of the row order. The table's B1/B2 labels are kept as originally named
(tied to plan section numbers, §4.3/§4.4) to avoid renumbering churn; only the *execution
order* is swapped.

## Cursor worker environment

- `cursor-agent 2026.08.04-aaa8809`, logged in as `vadim@intersubjective.space`.
- `composer-2.5` (non-fast) confirmed present in `cursor-agent models` listing.
- Runner: `~/.claude/skills/overseer/scripts/run_cursor_worker.sh`.

## Checkpoints

### A1 — Server `evaluationReceived` use case (§4.1)

**What changed**
- Added `EvaluationReceivedResult` / `EvaluationReceivedRow` + `EvaluationReceivedTrustTone` (`evaluation_received_result.dart`, `evaluation_received_trust_tone.dart`).
- Implemented `EvaluationCase.evaluationReceived` (named per-reviewer rows, `windowClosed` gate, tone via `reviewValueToBin` with `noBasis` sentinel).
- Kept `EvaluationCase.evaluationSummary` as a thin aggregate adapter over `evaluationReceived` so existing GraphQL field (`query_evaluation.dart`) and client `fetchSummary` remain unchanged until §4.5/A3.
- Dropped `noBasis` filter from `listEvaluationsForEvaluatedUser` (status filter retained); deleted `countDistinctEvaluatorsForEvaluated` from port, Drift repo, mock, and test doubles.
- Tests: `evaluationReceived` group in `evaluation_case_test.dart`, `evaluation_received_trust_tone_test.dart`.

**Judgement calls**
- **GraphQL stability:** did not touch `query_evaluation.dart` / `gql_v2_dto_maps.dart` — left `evaluationSummary` resolver wired to the adapter method; new `evaluationReceived` GraphQL field deferred to unit A3 (§4.5).
- **Participant guard / `beaconTitle` leak:** accepted plan default (no participant check; title returned even when `windowClosed: false`) — matches pre-change entitlement model.

**Commit:** `170809b5` — Server: add evaluationReceived use case with named per-reviewer rows.

**Verification**
```bash
cd packages/server && dart test test/domain/evaluation/evaluation_case_test.dart test/domain/evaluation/evaluation_received_trust_tone_test.dart test/domain/use_case/coordination_case_revert_test.dart  # 68 passed
./scripts/check-custom-lints.sh packages/server  # exit 0, baseline 0
```
Client untouched (no compile break expected until GraphQL codegen in C1/A3).

**Overseer review: ACCEPTED.** Independently reran the three test files (68 passed) and
`./scripts/check-custom-lints.sh packages/server` (0, baseline 0) from a clean shell.
Confirmed zero remaining source references to `countDistinctEvaluatorsForEvaluated`
(only a stale gitignored compiled binary at `packages/server/bin/tentura` matched, not
source). Verified `evaluationReceivedTrustToneFromValue` correctly special-cases
`noBasis` before falling through to `reviewValueToBin`, so D6 holds. Verified
`evaluationToneFromValues`/`evaluationSummaryAggregates` (the old aggregate helpers,
now reachable with un-filtered `noBasis` rows via the `evaluationSummary` adapter)
already `default`/ignore any value outside `neg2..pos2`, so `noBasis` rows still don't
skew the legacy aggregate tone/counts — no regression there. `buildEvaluationSummaryGraphqlPayload`
in `evaluation_summary_rules.dart` is pre-existing dead code (only referenced by its own
test), unrelated to this unit, left alone correctly.

(Appended chronologically below as units complete.)

### A2 — Cross-beacon finalized evaluations port + use case (§4.2)

**What changed**
- Added `CrossBeaconEvaluationRecord` (`domain/entity/evaluation/cross_beacon_evaluation_record.dart`) and `EvaluationsWrittenAboutViewerRow` (`evaluations_written_about_viewer_row.dart`) for repository vs use-case layers.
- Extended `EvaluationRepositoryPort` with `listFinalizedEvaluationsBetween`; implemented in `evaluation_repository.dart` via `customSelect` joining `beacon_evaluation` to `beacon`, filtering `status == final_` only (not `countsTowardSummary`), closed beacon statuses (`4` legacy + `6`), ordered `updated_at DESC`. Includes `noBasis` rows (no value filter).
- Added `EvaluationCase.evaluationsWrittenAboutMeBy` — calls repo with `evaluatorId: authorOfReviewsId`, `evaluatedUserId: viewerId`; maps tone via `evaluationReceivedTrustToneFromValue` (same sentinel as §4.1).
- Mock + test doubles updated (`evaluation_repository_mock.dart`, `_FakeEvaluationRepository`, `_TrackingEvaluationRepository`).
- Tests: `evaluationsWrittenAboutMeBy` group in `evaluation_case_test.dart` (empty, tone/noBasis mapping, pair scoping).

**Judgement calls**
- **Closed-beacon filter:** SQL adds `b.status IN (4, 6)` so mid-window (`reviewOpen`) requests never surface even if a stray row existed — stricter than `final_` alone.
- **Index finding:** `beacon_evaluation` has PK `(beacon_id, evaluator_id, evaluated_user_id)` only; no index on `(evaluator_id, evaluated_user_id, status)`. Cross-beacon profile query may seq-scan at scale — flagged, no migration added (out of unit scope per plan §3.4 note).
- **JWT enforcement:** deferred to GraphQL resolver (unit A3); use case trusts caller-supplied `viewerId`/`authorOfReviewsId` pair.

**Commit:** `3e4e27b8` — Server: add cross-beacon finalized evaluations query (§4.2).

**Verification**
```bash
cd packages/server && dart test test/domain/evaluation/ test/domain/use_case/evaluation/  # 86 passed
cd packages/server && dart test test/domain/use_case/coordination_case_revert_test.dart  # 27 passed
./scripts/check-custom-lints.sh packages/server  # exit 0, baseline 0
```

**Overseer review: ACCEPTED.** Independently reran `test/domain/evaluation/`,
`test/domain/use_case/evaluation/`, and `coordination_case_revert_test.dart` (113 passed)
and `check-custom-lints.sh packages/server` (0, baseline 0). Verified the `b.status IN
(4, 6)` filter against `lib/domain/entity/beacon_status.dart`: smallint `4` is a real
legacy `PENDING_REVIEW → closed` mapping (`fromSmallint`), not an invented value — the
extra beacon-status guard is correct and consistent, not just `status == final_` alone.
Verified `customSelect` with parameterized `Variable<...>` bindings (no string
interpolation of caller input) is the established pattern across nearly every file in
`data/repository/` — this unit's raw-SQL join is idiomatic here, not a deviation.
Confirmed no `noBasis` filter was reintroduced and `evaluationReceivedTrustToneFromValue`
is reused for tone mapping, consistent with A1.

### A3 — GraphQL API wiring (§4.5)

**What changed**
- Added GraphQL query fields `evaluationReceived` and `evaluationsWrittenAboutMeBy` to `query_evaluation.dart` (registered in `all`); left `evaluationSummary` untouched.
- JWT enforcement: `userId` / `viewerId` from `getCredentials(args).sub`; client `id` arg is beacon id (`evaluationReceived`) or profile-owner user id (`evaluationsWrittenAboutMeBy`).
- New GraphQL object types in `custom_types.dart`: `EvaluationReceived`, `EvaluationReceivedRow`, `EvaluationsWrittenAboutViewerRow` (all registered in `customTypes`).
- Mappers in `gql_v2_dto_maps.dart`: `evaluationReceivedToGqlMap`, `evaluationReceivedRowToGqlMap`, `evaluationsWrittenAboutViewerRowToGqlMap`.
- Reused A1 `gql_public` DTOs (`EvaluationReceivedResult` / `EvaluationReceivedRow`); no new gql_public files — profile rows map from domain `EvaluationsWrittenAboutViewerRow`.

**Judgement calls**
- **Shape mismatch:** `evaluationsWrittenAboutMeBy` returns a distinct GraphQL type `EvaluationsWrittenAboutViewerRow` (not `EvaluationReceivedRow`) because the domain row carries `beaconId`, `beaconTitle`, `beaconClosedAt`, `evaluatorId`, `evaluatedUserId` instead of reviewer display fields.
- **`tone` as string:** `EvaluationReceivedTrustTone.name` → `"up"` / `"down"` / `"noChange"` / `"noBasis"` (no GraphQL enum type in this codebase).
- **`reviewerRole` as int:** matches existing `EvaluationParticipant.role` GraphQL field (`dbValue` 0–3).

**Commit:** `52e0145f` — Server: wire evaluationReceived GraphQL API (§4.5).

**Verification**
```bash
cd packages/server && dart test test/domain/evaluation/ test/domain/use_case/evaluation/  # 86 passed
cd packages/server && dart analyze   # no compile errors in changed files; package-wide info-level debt unchanged
./scripts/check-custom-lints.sh packages/server  # exit 0, baseline 0
```
No server GraphQL snapshot/introspection test references `evaluationSummary` (grep under `packages/server/test/`).

**Overseer review: ACCEPTED.** Independently reran `test/domain/evaluation/` +
`test/domain/use_case/evaluation/` (86 passed), `dart analyze` (0 error-severity issues,
2191 info-level pre-existing debt, same count check-custom-lints already tolerates), and
`check-custom-lints.sh packages/server` (0, baseline 0). Confirmed `EvaluationParticipantRole.dbValue`
is a real existing getter (not invented). Confirmed `.toUtc().toIso8601String()` for
`occurredAt`/`beaconClosedAt` matches the codebase's established UTC-serialization
convention from the recent issue-112 timezone-fix work. `evaluationSummary` field left
byte-for-byte untouched in `query_evaluation.dart`. New types/mappers structurally mirror
the existing `gqlTypeEvaluationSummary`/`evaluationSummaryToGqlMap` pattern.

### B2 — AttentionEventType + policy + contract layer (§4.4, §5.3 server mechanism)

**What changed**
- Added `AttentionEventType.trustGivenChanged` / `trustReceivedChanged` and `AttentionDestinationKind.receivedReviews` (`wireName: 'received_reviews'`).
- Added `AttentionRecipientRoleFacts.trustDirection` (`String?`) for direction-encoded `_presentationKey` values (`trust_given_changed_up|down|neutral`, `trust_received_changed_up|down|neutral`).
- Updated all exhaustive `attention_policy.dart` switches; `_presentationKey` now takes `role` and delegates direction via `_trustChangePresentationKey`.
- Serialized `trustDirection` in `attention_dispatch_repository.dart` `_rolePayload`.
- Contract: two new `eventTypes[]` rows; both listed in `pendingProducerEventTypes` until B1 (§4.3) adds intent builders.
- Tests: contract mirrors (server + client), `attention_policy_test.dart` fixtures + `received_reviews` destination matcher.
- **Deferred per plan:** client `destination_map.dart` branch (later C2 unit); `AttentionIntentCase` builders / call-site wiring (B1).

**Judgement calls**
- **`trustDirection` values:** `'up'`, `'down'`, `'noChange'` documented on the field; mirrors `EvaluationReceivedTrustTone` naming without importing evaluation types. Null/`noChange`/any other value → `_neutral` presentation key.
- **`NotificationCategory`:** `connections` for both events (social/relationship signal, same bucket as `mutualConnectionFormed`/`inviteAccepted`).
- **`AttentionAccessPolicy`:** `beaconContent` for both (per plan — gates `beaconTitle` in payload even though `trustGivenChanged` routes to profile).
- **Destinations:** `trustGivenChanged` → `profile` + `role.targetEntityId`; `trustReceivedChanged` → `receivedReviews` + `role.beaconId`.
- **Contract `recipientCategory`:** `review_participant` (matches `AttentionRecipientReason.reviewParticipant` used by B1 builders).
- **Contract `destinationFamily`:** `profile` / `received_reviews`.
- **`pendingProducerEventTypes`:** both new types listed — required because `attention_intent_case_test.dart` asserts every non-pending contract type has a migrated fixture, and B1 has not landed yet.
- **`m0129.dart` finding:** actor-erasure rebuild sets `role_facts` to `{'canReadBeaconContent': ...}` only — `trustDirection` drops like every other non-boolean field; no migration edit needed.

**Commits:** `db6c53ac` (enum/policy/dispatch), `d9af62d1` (contract + mirrors), `6413018e` (policy test fixtures).

**Verification**
```bash
cd packages/server && dart run build_runner build -d   # after freezed field
cd packages/server && dart test test/domain/attention/ test/architecture/  # 70 passed
cd packages/server && dart analyze   # 0 errors (2191 info-level pre-existing)
cd packages/client && flutter test test/architecture/updates_event_contract_test.dart  # 1 passed
./scripts/check-custom-lints.sh packages/server  # exit 0, baseline 0
```

**Overseer review: ACCEPTED.** Independently reran `test/domain/attention/` + `test/architecture/`
(70 passed), `dart analyze` (0 error-severity issues), `check-custom-lints.sh packages/server`
(0, baseline 0), and the client contract mirror (`flutter test
test/architecture/updates_event_contract_test.dart`, 1 passed). Verified the worker's
`pendingProducerEventTypes` discovery is real and correctly used: confirmed
`attention_intent_case_test.dart:299-318` ("every non-pending compact-contract type has a
migrated fixture") excludes any `eventType` listed in `pendingProducerEventTypes` from
requiring an `AttentionIntentCase` fixture — exactly the mechanism needed to let this unit
land cleanly before B1 adds the actual builders. **Action item for B1:** once
`AttentionIntentCase.trustGivenChanged`/`trustReceivedChanged` builders exist, remove both
entries from `pendingProducerEventTypes` in `docs/contracts/updates-event-contract.json`
(both server and any client mirror) and add matching fixtures to
`attention_intent_case_test.dart`, or that test will not actually exercise the new builders.
Confirmed `_presentationKey`'s new `role` parameter and `_trustChangePresentationKey` helper
match the requested `_up`/`_down`/`_neutral` encoding exactly, with a safe default-to-neutral
fallback. Confirmed `_rolePayload` and all exhaustive switches were updated. Confirmed
`destination_map.dart` (client) was correctly left untouched per instruction (route doesn't
exist yet).

### B1 — Updates events at review finalization (§4.3)

**What changed**
- Added `ReviewFinalizationResult` / `FinalizedTrustPair` (`review_finalization_result.dart`); widened `ReviewFinalizationPort.closeAndFinalize` return type.
- Added `beaconTitle` to `ReviewCloseSnapshot`; populated from `beaconRow.title` in `evaluation_repository.closeReviewWindow`.
- `ReviewFinalizationCase` now returns `didClose`, `beaconTitle`, and `pairs` (bins via `reviewValueToBin`, same skip-null rule as `_recordCommitmentEvidence`).
- Added `AttentionIntentCase.trustGivenChanged` / `trustReceivedChanged` hand-built builders with inline copy and `trustDirection` on role facts.
- Wired both builders into `EvaluationCase.closeNow` and `AttentionExpirySweepCase.runDue` after finalization, inside existing attention transactions.
- Cleared `pendingProducerEventTypes` for both trust events; added `attention_intent_case_test.dart` fixtures; updated contract-test mirrors.
- Added shared `kPathBeaconView` to `lib/consts.dart` for server action URLs.

**Judgement calls**
- **`NotificationKind`:** `reviewReady` for both builders (review-lifecycle family; legacy push/outbox only).
- **`AttentionDispatchIntent.beaconId`:** set on both builders — matches `requestStatusChanged` hand-built pattern (`attention_intent_case.dart:605`).
- **`trustReceivedChanged` destination field:** confirmed B2 policy reads `role.beaconId` for `AttentionDestinationKind.receivedReviews` `targetEntityId`; set `role.targetEntityId: beaconId` (redundant with beacon id on role, but consistent with other beacon-scoped intents).
- **`trustGivenChanged` `role.targetEntityId`:** `evaluatedUserId` (counterpart profile routing per policy).
- **Neutral-bin suppression:** call sites skip `TrustBin.noEffect` pairs (plan §9 Q1 default); B2's three-way presentation keys remain available if product later surfaces neutral cards without policy changes.
- **`producers[]`:** left unchanged — one row per use-case file convention (`evaluation_case.dart` already has `reviewOpened`; `attention_expiry_sweep_case.dart` has `requestStatusChanged`).
- **Copy strings:** trust given — title `Trust update`, bodies direction-aware with request title; trust received — titles `Someone trusts you more/less` / `Someone reviewed you`, bodies include D4's "and their network" framing; empty display names fall back to `them`/`Someone`.

**Commits:** `222ffd4d` (return widening), `ac3c61a8` (intent builders), `bcec3e2b` (call sites), `308a9f2b` (contract + fixtures).

**Verification**
```bash
cd packages/server && dart run build_runner build -d
cd packages/server && dart test test/domain/evaluation/ test/domain/use_case/evaluation/ test/domain/attention/ test/architecture/  # 158 passed
cd packages/server && dart analyze   # 0 errors (2197 info-level pre-existing)
cd packages/server && dart test test/app/di_smoke_test.dart  # 2 passed
./scripts/check-custom-lints.sh packages/server  # exit 0, baseline 0
```

**Overseer review: ACCEPTED.** Independently reran the full test set (158 passed), the DI
smoke test (2 passed, both prod and dev graphs resolve — confirms the widened
`ReviewFinalizationPort` return type didn't break Injectable wiring), `dart analyze`
(0 error-severity issues), and `check-custom-lints.sh packages/server` (0, baseline 0).
Verified `kPathBeaconView` added to the shared root `lib/consts.dart` (`'/beacon/view'`)
matches the client's own `packages/client/lib/consts.dart` value exactly — no divergence.
Verified against the live `attention_policy.dart` `_destination` switch that
`trustReceivedChanged`'s destination `targetEntityId` really does come from `role.beaconId`
(not `role.targetEntityId`), confirming the worker's stated judgement call was checked
against the real B2 code, not assumed. Verified copy strings avoid MeritRank internals
(no "bin"/numeric score) and correctly use D4's "and their network" as descriptive prose.
Verified `pendingProducerEventTypes` is now `[]` and `attention_intent_case_test.dart`
gained real fixtures for both event types (not just contract bookkeeping). Both call sites
correctly skip `TrustBin.noEffect` pairs per the Q1 default, and both use fresh
per-pair-per-direction `sourceEventKey`s. This closes out all server-side work (A1-A3,
B1-B2) — client units (C1 onward) can now build against a stable GraphQL/Updates surface.

### C1 — Client evaluation domain/data layer (§5.1)

**Recovery note:** This unit recovered from an interrupted prior worker session that had already landed `schema.graphql` and the two `.graphql` documents before infrastructure cut the session off; this continuation ran codegen, entities, routing, and repository methods on top of that work.

**What changed**
- `packages/client/lib/data/gql/schema.graphql` — added `evaluationReceived` / `evaluationsWrittenAboutMeBy` query fields and `v2_EvaluationReceived` / `v2_EvaluationReceivedRow` / `v2_EvaluationsWrittenAboutViewerRow` types (verified against server A3 shapes).
- New Ferry documents: `evaluation_received.graphql`, `evaluations_written_about_me_by.graphql`; codegen via `dart run build_runner build -d` (generated `_g/` artifacts gitignored).
- `build_client.dart` — registered `'EvaluationReceived'` and `'EvaluationsWrittenAboutMeBy'` in `_tenturaDirectOperationNames` for V2 direct routing.
- New Freezed domain entities: `evaluation_received.dart` (`EvaluationReceivedTrustTone`, `EvaluationReceivedRow`, `EvaluationReceived`) and `evaluations_written_about_viewer.dart` (`EvaluationsWrittenAboutViewerRow`).
- `evaluation_repository.dart` — added `evaluationReceived(beaconId)` and `evaluationsWrittenAboutMeBy(authorOfReviewsId)` with GraphQL→entity mapping; left `fetchSummary` untouched (C2 migration).
- Tests: `evaluation_received_trust_tone_test.dart`; extended `FakeEvaluationRepository` in `evaluation_case_test.dart`.

**Judgement calls**
- **`reviewerRole`:** stored as `int` (0–3) on `EvaluationReceivedRow`, not `EvaluationParticipantRole` — client enum lacks `formerCommitter(3)` (`evaluation_participant.dart` has only author/committer/forwarder); UI layer can map int→label in C2.
- **`trustTone` wire mapping:** `EvaluationReceivedTrustTone.fromWire(String)` maps server `tone.name` strings (`up`/`down`/`noChange`/`noBasis`); unrecognized values fall back to `noChange` (mirrors B2 `_trustChangePresentationKey` neutral default, distinct from `noBasis`).
- **DateTime parsing:** `DateTime.parse(raw).toUtc()` for `occurredAt` and `beaconClosedAt` — matches issue-112 UTC convention used server-side (`.toUtc().toIso8601String()`) and client `beacon_room_repository.dart` read paths.
- **Entity field naming:** domain uses `trustTone` (not server wire `tone`) to keep Flutter/design-system `TenturaTone` mapping at UI layer per clean-architecture rule.
- **No `EvaluationCase` changes:** deferred — no cubit consumer yet in this unit.

**Commits:** `17b42c96` (schema + `.graphql` docs), `e063728f` (entities + `build_client.dart`), `b06820e0` (repository + tests + journal).

**Verification**
```bash
cd packages/client && dart run build_runner build -d
cd packages/client && flutter analyze lib/features/evaluation/   # pre-existing warnings only; 0 errors in new code
cd packages/client && flutter test test/features/evaluation/   # 53 passed
./scripts/check-custom-lints.sh packages/client                # exit 0, baseline 111 unchanged
```

**Overseer note on the interruption:** the first two launch attempts for this unit were
killed by background-task infrastructure within seconds, before any work happened (empty
logs, clean worktree both times — nothing to preserve). The third attempt ran in the
background and produced real work (schema.graphql + 2 `.graphql` docs, uncommitted) before
also being killed mid-session. That partial work was inspected, found well-formed and
correctly matching the A3 server shapes (alphabetized fields, correct types), and preserved.
A recovery worker was then launched **in the foreground** (bypassing whatever was killing
background sessions) with an explicit prompt describing the partial state and continuing
from GraphQL codegen onward — this is the run captured above.

**Overseer review: ACCEPTED.** Independently reran `dart run build_runner build -d` (0
outputs — already up to date, confirming the worker's own codegen run was already
complete and committed correctly), `flutter analyze lib/features/evaluation/` (14 issues,
all pre-existing/unrelated to this unit's files — verified the one hit inside
`evaluation_repository.dart` at line 176 predates this unit by diffing against the pre-C1
commit), `flutter test test/features/evaluation/` (53 passed), and
`check-custom-lints.sh packages/client` (109, down from baseline 111 — strictly better, not
a regression). Verified the `DateTime.parse(...)` (no `.toLocal()`) convention against
`beacon_room_repository.dart`'s existing read paths, confirming the worker's stated
UTC-handling judgement call was checked against real code. Domain entities correctly avoid
Flutter/design-system imports per clean-architecture rule. `fetchSummary`/old
`evaluation_summary.dart` left untouched as instructed.

### C2 — Received reviews screen + tile + routing (§6.3)

**What changed**
- New `ReceivedReviewsScreen` (`@RoutePage()`, `@PathParam('id')` beacon id) + `ReceivedReviewsView` body (extracted for widget tests without AutoRouter).
- New `ReceivedReviewsCubit` — thin single-repo cubit injecting `EvaluationRepository` via `fromGetIt`; **did not reuse `EvaluationCubit`** (write-flow oriented: participants, submit, finalize).
- New `ReceivedReviewTile` — avatar, role `TenturaTypeLabel`, trust line with tinted-circle glyph (`_TrustToneGlyph`, pattern from `coordination_ui.dart` pill tints), reason tags, note, `compactRelativeTimeAgo` (same helper as `UpdatesReceiptCard`).
- Route: `kPathReceivedReviews = '/beacon/reviews-received'`; `ReceivedReviewsRoute` in `root_router.dart` + `home_tab_branches.dart` branch + `_browsePathOwners` entry (owner `HomeTab.work`).
- l10n (en+ru): screen title/generic, empty states, trust-direction labels, `evaluationRoleFormerCommitter`, review-window-status link.
- Widget tests: `received_reviews_screen_test.dart` (rows, both empty states, `noBasis` vs `noChange`).

**Judgement calls**
- **Route path:** `/beacon/reviews-received/:id` — distinct from `/beacon/review/:id` (`ReviewContributionsRoute`); matches B2 `AttentionDestinationKind.receivedReviews` wire name family.
- **Cubit:** new `ReceivedReviewsCubit` rather than extending `EvaluationCubit` — read-only fetch, no overlap with write/submit state machine.
- **Role labels:** reused `evaluationRoleAuthor` / `evaluationRoleHelpOfferer` / `evaluationRoleForwarder`; added `evaluationRoleFormerCommitter` for int `3` (client `EvaluationParticipantRole` still lacks this value).
- **Date display:** `compactRelativeTimeAgo` from `ui/utils/relative_time.dart` via `TenturaMetaText` — matches Updates receipt cards.
- **§6.6 deferred:** `EvaluationSummaryCard` untouched (next unit C3 retires it with entry points).
- **`destination_map.dart`:** not updated here (D1 / Updates unit); route exists for future `received_reviews` deep links once map branch lands.

**Commits:** `1004ff17` (l10n), `4b9f10fe` (tile), `0265e4cc` (screen+cubit), `19427f16` (routing), `4ea6fc16` (tests).

**Verification**
```bash
cd packages/client && flutter gen-l10n && dart run build_runner build -d
cd packages/client && flutter analyze lib/features/evaluation/ lib/app/router/  # 0 new errors (pre-existing warnings only)
cd packages/client && flutter test test/features/evaluation/   # 57 passed
./scripts/check-custom-lints.sh packages/client                # 109, baseline 111 unchanged
```

**API for next unit (C3):** navigate with `ReceivedReviewsRoute(id: beaconId)` or `pushPath('$kPathReceivedReviews/$beaconId')`; screen constructor `ReceivedReviewsScreen({@PathParam('id') id})`.
