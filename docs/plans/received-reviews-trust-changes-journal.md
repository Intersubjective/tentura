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
| A2 | Server: `listFinalizedEvaluationsBetween` port method + `CrossBeaconEvaluationRecord` + Drift impl + `evaluationsWrittenAboutMeBy` use case | §4.2 | pending |
| A3 | Server: GraphQL API wiring (`query_evaluation.dart`, `custom_types.dart`, `gql_v2_dto_maps.dart`, `gql_public` DTOs) | §4.5 | pending |
| B1 | Server: widen `closeAndFinalize` return + `ReviewCloseSnapshot.beaconTitle` + `AttentionIntentCase` builders + call sites (`EvaluationCase.closeNow`, `AttentionExpirySweepCase.runDue`) | §4.3 | pending |
| B2 | Server+client: `AttentionEventType` + exhaustive `attention_policy.dart` switches + `AttentionDestinationKind.receivedReviews` + contract JSON (both copies) + `attention_policy_test.dart` fixtures + client `destination_map.dart` wire-name branch | §4.4 | pending |
| C1 | Client: domain entity `evaluation_received.dart`, repository methods + `.graphql` docs, `schema.graphql` update, `build_client.dart` operation names, codegen | §5.1 | pending |
| C2 | Client: `ReceivedReviewsScreen` + `ReceivedReviewTile` + route wiring (`root_router.dart`, `consts.dart`, `home_tab_branches.dart`) + `EvaluationSummaryCard` fix/replace | §6.3, §6.6 | pending |
| C3 | Client: entry points — `ReviewWindowBannerHost`/`beacon_operational_header_card.dart` always-visible CTA + `ClosedRequestBanner` CTA | §6.4 | pending |
| D1 | Client: `TrustChangeReceiptCard` + presentation-key direction threading + `updates_receipt_display_copy.dart` + `updates_screen.dart` dispatch | §5.3, §6.2 | pending |
| E1 | Client: `ProfileReviewsAboutMeCubit` + `reviews_about_me_from_profile_sliver.dart` wiring into `profile_view_screen.dart` | §5.2, §6.5 | pending |
| F1 | Client: l10n keys (en+ru) + `pubspec.yaml` version bump + `MIN_CLIENT_VERSION` decision per `DEV_GUIDELINES.md` | §6.7, versioning rule | pending |
| F2 | Overseer-run: full plan-level verification sweep against §7 acceptance table, gap-fill any missing test coverage, close out | §7 | pending |

Dependencies: A1→A2 (repository file overlap), A2→A3 (needs new types), B1 depends on A1 (evaluation_case.dart churn) landing first to avoid merge pain, B2 depends on B1. C1 depends on A1-A3+B2 (GraphQL schema/contract must be stable before client codegen). C2/C3 depend on C1. D1 depends on B2+C1. E1 depends on A2+C1. F1 last (touches version files), F2 last of all.

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

(Appended chronologically below as units complete.)
