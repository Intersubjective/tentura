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
| B1 | Server: widen `closeAndFinalize` return + `ReviewCloseSnapshot.beaconTitle` + `AttentionIntentCase` builders + call sites (`EvaluationCase.closeNow`, `AttentionExpirySweepCase.runDue`) | §4.3 | pending |
| B2 | Server+client: `AttentionEventType` + exhaustive `attention_policy.dart` switches + `AttentionDestinationKind.receivedReviews` + contract JSON (both copies) + `attention_policy_test.dart` fixtures + client `destination_map.dart` wire-name branch | §4.4 | done |
| C1 | Client: domain entity `evaluation_received.dart`, repository methods + `.graphql` docs, `schema.graphql` update, `build_client.dart` operation names, codegen | §5.1 | pending |
| C2 | Client: `ReceivedReviewsScreen` + `ReceivedReviewTile` + route wiring (`root_router.dart`, `consts.dart`, `home_tab_branches.dart`) + `EvaluationSummaryCard` fix/replace | §6.3, §6.6 | pending |
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
