# Commitment truth rework — implementation journal

## Objective

Implement `docs/plans/commitment-truth-rework-plan.md` (revision 3) end to end:
append-only `beacon_commitment_event` truth source replacing the mutable
`beacon_help_offer_coordination` row as the record of participation facts,
across phases P1–P10.

## Orchestration

Run via the `overseer` skill: fresh Cursor CLI workers (`composer-2.5`, non-fast),
one per manifest unit below, sequential, reviewed and committed by the
orchestrator (Claude) after each unit.

## Repository state at start

- Branch: `feat/commitment-truth-rework` (created from `main` @ `ed7e4773`).
- `main` is 93 commits ahead of `origin/main` (unpushed local history — pre-existing,
  not part of this work).
- Pre-existing untracked files at branch creation (**not owned by this plan, do not
  touch/delete**): `dart-defines`, `docs/plans/graph-navigation-implementation-guide.md`,
  `docs/plans/graph-navigation-rework-plan.md`, `graph-ego-neighbors-layout-issue.md`,
  `key.fb`, `out.key`, `product_testing_compact_buglist.md`,
  `product_testing_detailed_report.md`. `docs/plans/commitment-truth-rework-plan.md`
  itself was also untracked at branch creation — it is the plan source, keep it,
  commit it with P1 if not already tracked.
- Migrations currently end at `m0139` is new; last existing is `m0138`.
- No prior branch/journal for this plan existed.

## Ordered unit checklist

Strict order per plan §13: P1 → P2 → P3 → P4 → P5 → P6 → P7 → P8 → P9 → P10.
P3 and P8 are split into sub-units below for worker reliability; dependencies
noted. Release-boundary note (informational only — we are not pushing/opening
PRs, everything lands as sequential commits on one local branch): plan calls
P1+P2+P3(+P3.11)+P8.1 the "core", P4–P10 separate follow-on PRs in real
deployment. We still commit once per phase (plan §0.5 format:
`feat(commitment): P<N> — <description>`, or `P<N>.<M>` for split units).

- [x] U01 — P1: foundation (migration m0139, Drift tables/entities, pure
      predicates, port+repository, query case, P1 tests)
- [x] U02 — P2: record facts at all write points (help_offer_case,
      coordination_case, user_block_case, remove `deleteForCommit`, P2 tests)
- [x] U03 — P3.1+P3.2+P3.3: Cancel/Delete gates switch to `everHadCommitter`;
      `formerCommitter` role added everywhere it's exhaustively matched
- [x] U04 — P3.4: review-composition graph builder rewritten on commitment
      events
- [x] U05 — P3.5+P3.6+P3.7: Close review-window trigger, `unansweredAtClose`
      write, `_canCloseNow` former-committer exclusion, reopen limit
- [x] U06 — P3.8+P3.9+P3.10: withdraw forbidden in Wrapping up, response
      downgrade forbidden after acknowledgement, room-admission-requires-
      acknowledgement invariant (+ client UI guard)
- [x] U07 — P3.11: client truth alignment for Close (**release-blocking per
      plan**) — server `stakeState`/`offerKind` on coordination row, client
      `CommitmentStakeState`, `helpOfferIsCommitter` rewrite, My Work counter
      wiring (depends on P8.1 field `everAcknowledgedCommitterCount` — see U09)
- [x] U08 — P3.12: full P3 gate-scenario test suite (18 scenarios) — run after
      U03–U07 land
- [x] U09 — P8.1: server `canCancel`/`canDelete`/`everAcknowledgedCommitterCount`
      fields on `beaconDisplayStatuses` (needed by U07 p.4 — see plan §13)
- [ ] U10 — CORE VERIFY: full verify matrix for P1+P2+P3+P8.1 as integrated
      whole per plan §12.2 subset + `kDefaultMinClientVersion` bump (§12.3)
- [ ] U11 — P4: `releaseCommitment` (server use case, exception code,
      notification kind `commitmentReleased`, GraphQL, client case/cubit/UI,
      l10n, tests)
- [ ] U12 — P5: remove auto-admit (D4), direct-author-forward chip/sort
- [ ] U13 — P6: "Enough help" Forward-primary + backup offers (D2 A+B)
- [ ] U14 — P7: My Work offer-response-state row (D3)
- [ ] U15 — P8 (rest): P8.2+P8.3+P8.4+P8.5 — client gate wiring, close-sheet
      patch, l10n, tests
- [ ] U16 — P9: issue #108 — diagnose-first, Delete explanation, Close-now
      CTA batch query, idempotency, e2e regression test
- [ ] U17 — P10: docs (§12.1 table), final verify matrix (§12.2), manual
      scenario walkthrough, version bump confirmation

## Acceptance / verification commands (plan §0.3, run after every phase)

```bash
cd packages/tentura_lints && dart test
cd packages/server && dart test              # see §11.2 re: -x pg
./scripts/check-custom-lints.sh packages/server
./scripts/check-custom-lints.sh packages/client
cd packages/client && flutter test
bash scripts/check-user-facing-terminology.sh
```

Custom-lint baseline: client must not exceed value in
`scripts/custom-lint-baseline.txt` (plan text says 112 — **defer to the file**,
not the plan prose); server 0.

## Non-negotiable rules (plan §0.1, restated for workers)

- Never reorder existing enum values serialized by index
  (`HelpOfferCoordinationExceptionCode`, `EvaluationExceptionCode`) — append only.
- Never change the meaning of existing DB numeric codes.
- Never hand-edit generated files (`*.g.dart`, `*.freezed.dart`, `*.gr.dart`,
  `*.config.dart`, l10n `_g`, `*.schema.dart`).
- Never edit/delete existing migrations `m0001…m0138`; new schema changes are
  new migrations only.
- Never introduce a domain entity/table/route named `Request`.
- No raw visual constants in client UI — design-system tokens only.
- No scope expansion beyond the plan; unplanned necessary changes go in plan
  §14 "Открытые вопросы", not into ad hoc extra work.
- Client never parses server error codes for UX; gates are pre-computed flags.

## Unresolved decisions / blockers

- `hasSuccessfulHelpOfferResult` / `helpOfferRowSettled` in
  `beacon_closure_readiness.dart` still read `coordinationResponse == useful`
  for settlement/readiness heuristics (not committer/Close-contract truth).
  Left unchanged — plan scoped committer truth to `helpOfferIsCommitter` and
  `expectedRequiresReviewWindowForState` only; settlement copy may still reflect
  stale author response until a later UX pass.

## Checkpoints

### 2026-08-05 — U01 P1 foundation (worker)

**Done:** Implemented plan §3 (P1.1–P1.6) in full.

- **P1.1:** `m0139.dart` — 13 migration steps in plan order (table, indexes,
  `offer_kind`/`stake_state`/`review_reopen_count`, backfills 8a→11a, stake_state
  projection UPDATE). Registered in `_migrations.dart`.
- **P1.2:** `BeaconCommitmentEvents` Drift table; `offerKind`/`stakeState` on
  `BeaconHelpOffers`; `reviewReopenCount` on `Beacons`; `HelpOfferEntity` +
  `_toEntity` mapping; `tentura_db.dart` registration; `build_runner` clean.
- **P1.3:** `CommitmentEventKind`, `CommitmentEvent`, `commitment_consts.dart`,
  `commitment_state.dart` (self-sorting pure predicates).
- **P1.4:** `CommitmentRepositoryPort` + `CommitmentRepository` (`customInsert`
  without `seq`, transactional `stake_state` projection update).
- **P1.5:** `CommitmentQueryCase` — 4 methods only; no `hasMaterialRoomWork`.
- **P1.6:** `commitment_state_test.dart` — all 14 numbered scenarios green.

**Files touched (committed):**
- `packages/server/lib/data/database/migration/m0139.dart`, `_migrations.dart`
- `packages/server/lib/data/database/table/beacon_commitment_events.dart`,
  `beacon_help_offers.dart`, `beacons.dart`, `tentura_db.dart`
- `packages/server/lib/domain/entity/help_offer_entity.dart`
- `packages/server/lib/data/repository/help_offer_repository.dart`,
  `commitment_repository.dart`
- `packages/server/lib/consts/commitment_consts.dart`
- `packages/server/lib/domain/commitment/*`
- `packages/server/lib/domain/port/commitment_repository_port.dart`
- `packages/server/lib/domain/use_case/commitment_query_case.dart`
- `packages/server/test/domain/commitment/commitment_state_test.dart`
- `hasura/metadata.json`

**Tests run (all passed):**
- `cd packages/server && dart run build_runner build -d`
- `cd packages/server && dart test test/domain/commitment/commitment_state_test.dart` → 16 tests
- `cd packages/server && dart test -x pg` → full non-pg suite green
- `cd packages/tentura_lints && dart test` → 18 tests
- `./scripts/check-custom-lints.sh packages/server` → 0 custom lint issues

**DB / Hasura:**
- Local Postgres (docker `postgres`) reachable. First `run_migrations_once` run
  recorded `0139` in `schema_version` without creating objects (pre-existing
  orphan version row); deleted row and re-ran — migration applied cleanly
  (`beacon_commitment_event` table + new columns verified via `docker exec psql`).
- `./scripts/hasura_apply_metadata.sh` → OK after migration (first attempt failed
  because columns did not yet exist).

**Commits (4, not pushed):**
- `1164b9bf` feat(commitment): P1.1+P1.2 — migration m0139, Drift tables, Hasura columns
- `1c6e6d66` feat(commitment): P1.3 — commitment event types and pure state predicates
- `0d190939` feat(commitment): P1.4+P1.5 — CommitmentRepository and CommitmentQueryCase
- `95e28dd1` feat(commitment): P1.6 — commitment_state unit tests (14 scenarios)

**Decisions:** Grouped P1.1+P1.2 in one commit (schema lands together per plan
guidance). No product behavior wired yet — P2+ will call `CommitmentRepository.record`.

**Remaining:** U02 (P2) — record facts at all write points.

### 2026-08-05 — U02 P2 record facts at write points (worker)

**Done:** Implemented plan §4 (P2.1–P2.5) in full.

- **P2.1:** `HelpOfferCase` injects `CommitmentRepositoryPort`; new offers record
  `offered`; `withdraw` records `withdrawnByHelper` instead of `deleteForCommit`.
- **P2.2:** `CoordinationCase` injects `CommitmentRepositoryPort` +
  `CommitmentQueryCase`; accept/decline/remove/setResponse write commitment events
  with idempotent transition checks (`acknowledged`, `acknowledgementSoftened`,
  `removedFromChat`, `readmittedToChat`).
- **P2.3:** `UserBlockCase._withdrawOffersByOfferer` records `blockedCleanup`
  (`reason = kBlockWithdrawReason`) instead of deleting coordination rows.
- **P2.4:** Removed `deleteForCommit` from port, repository, and all test stubs
  (`grep deleteForCommit packages/server` → empty).
- **P2.5:** Extended `help_offer_case_test` (withdraw records event, no row delete);
  new `coordination_case_commitment_events_test.dart` (accept/decline/remove/
  setResponse + idempotence); updated `user_block_case_test` (blockedCleanup);
  updated constructor wiring in admission-matrix, revert, graphql block tests;
  added `test/support/recording_commitment_repository.dart`.

**Test assertion updates (journal record):** `user_block_case_test` expectations
changed from `deleteForCommitCalls` to `commitment.recordCalls` with
`blockedCleanup` — prior tests explicitly asserted coordination-row deletion,
which P2 replaces with append-only events.

**Files touched (committed):**
- `packages/server/lib/domain/use_case/help_offer_case.dart`
- `packages/server/lib/domain/use_case/coordination_case.dart`
- `packages/server/lib/domain/use_case/user_block_case.dart`
- `packages/server/lib/domain/port/coordination_repository_port.dart`
- `packages/server/lib/data/repository/coordination_repository.dart`
- `packages/server/test/support/recording_commitment_repository.dart`
- `packages/server/test/domain/use_case/help_offer_case_test.dart`
- `packages/server/test/domain/use_case/coordination_case_commitment_events_test.dart`
- `packages/server/test/domain/use_case/user_block_case_test.dart`
- `packages/server/test/domain/use_case/coordination_case_revert_test.dart`
- `packages/server/test/domain/use_case/beacon_room_admission_matrix_test.dart`
- `packages/server/test/api/controllers/graphql/user_block_graphql_test.dart`
- `packages/server/test/domain/evaluation/evaluation_case_test.dart`
- `packages/server/test/domain/evaluation/evaluation_graph_test_repos.dart`
- `packages/server/test/domain/use_case/help_offer_case_mocks.mocks.dart`

**Tests run (all passed):**
- `cd packages/server && dart test -x pg` → 1211/1211 green (+11 new)
- `cd packages/tentura_lints && dart test` → 18/18 green
- `./scripts/check-custom-lints.sh packages/server` → 0 custom lint issues
- `cd packages/server && dart test --tags pg test/data/repository/user_block_withdrawal_gate_pg_test.dart` → 9/9 green (local Postgres reachable)

**Commits (4, not pushed):**
- `eb70b7f8` feat(commitment): P2.1 — record offered/withdrawn events in HelpOfferCase
- `b1509b75` feat(commitment): P2.2 — record commitment events in CoordinationCase
- `39cd192e` feat(commitment): P2.3+P2.4 — block cleanup events; remove deleteForCommit
- `5386679d` test(commitment): P2.5 — commitment event write-point tests
- `cba7bbd4` docs(commitment): U02 P2 journal checkpoint

**Decisions:** Idempotence helpers live as private methods on `CoordinationCase`
(check `currentStakeState`, `everAcknowledged`, and removed/readmitted event
sequence). `declineHelpOffer` snapshots `everAcknowledgedPair` before the
decline mutation (same pattern as plan's write-rule box). Gates (Cancel/Delete)
intentionally not switched — P3 scope.

**Remaining:** U04 (P3.4) — review-composition graph builder on commitment events.

### 2026-08-05 — U03 P3.1+P3.2+P3.3 gate switch and formerCommitter role (worker)

**Done:** Implemented plan §5 P3.1–P3.3 only (no P3.4+).

- **P3.1:** `BeaconCase.beaconCancel` gates on
  `CommitmentQueryCase.everHadCommitter(beaconId)`; injected
  `CommitmentQueryCase`, removed unused coordination/help-offer deps from
  `BeaconCase`.
- **P3.2:** `BeaconCase.deleteById` same gate (draft hard-delete path unchanged).
- **P3.3:** `EvaluationParticipantRole.formerCommitter(3)` + branches in
  `evaluation_reason_tags.dart`, `evaluation_summary_rules.dart`,
  `evaluation_visibility_rules.dart` (if-chain updated per plan point 4).
- **Tests:** extended cancel/delete gate tests with accept→withdraw scenarios via
  real `RecordingCommitmentRepository` + `CommitmentQueryCase`; extended
  evaluation visibility/reason-tag/summary tests for role 3.

**Tests run (all passed):**
- `cd packages/server && dart test -x pg` → 1216/1216 green (+5 new)
- `cd packages/tentura_lints && dart test` → 18/18 green
- `./scripts/check-custom-lints.sh packages/server` → 0 custom lint issues
- `dart run build_runner build -d` in packages/server (DI regen for BeaconCase)

**Decisions:** Removed `CoordinationRepositoryPort` / `HelpOfferRepositoryPort`
from `BeaconCase` constructor (only used by old gates). Added
`test/support/noop_commitment_query_case.dart` for other BeaconCase tests.
Cancel error description updated to plan wording (“ever had a committer”).

**Remaining:** U06 (P3.8+P3.9+P3.10) — withdraw forbidden in Wrapping up, response
downgrade forbidden, room-admission invariant.

### 2026-08-05 — U05 P3.5+P3.6+P3.7 close, closeNow, reopen limit (worker)

**Done:** Implemented plan §5 P3.5–P3.7 only.

- **P3.5:** `beaconClose` sets `requiresReviewWindow` from
  `CommitmentQueryCase.everHadCommitter`; before status transition records
  `unansweredAtClose` for active `offerKind == 0` offers without
  `everAcknowledged` (author actor, `reason = null`). Injected
  `CommitmentQueryCase`, `CommitmentRepositoryPort`, `HelpOfferRepositoryPort`
  into `EvaluationCase`.
- **P3.6:** Verified `_canCloseNow` still filters only roles 0 and 1 (roles 2
  and 3 skipped via `continue`). Added regression: former committer incomplete
  review does not block `closeNow`; current committer incomplete still blocks.
- **P3.7:** `BeaconRepositoryPort.reviewReopenCount` /
  `incrementReviewReopenCount` backed by `beacon.review_reopen_count`; 
  `reopenFromReview` throws `beaconNotClosable` / `Reopen limit reached` when
  count ≥ `kMaxReviewReopens` (1), increments after successful reopen in the
  same transaction.

**Tests run (all passed):**
- `cd packages/server && dart run build_runner build -d`
- `cd packages/server && dart test -x pg` → 1230/1230 green (+9 new)
- `cd packages/tentura_lints && dart test` → 18/18 green
- `./scripts/check-custom-lints.sh packages/server` → 0 custom lint issues

**Commits (3, not pushed):**
- `f86f35e5` feat(commitment): P3.5 — everHadCommitter close gate and unansweredAtClose events
- `5366aa1e` test(commitment): P3.6 — former committer does not block closeNow
- `a208b4c8` feat(commitment): P3.7 — review reopen count limit on BeaconRepository

**Decisions:** `unansweredAtClose` detection uses `!everAcknowledged(eventsForPair)`
  on active normal offers (aligned with display “no author response” idiom).
  `fetchByBeaconId` already returns only active rows (`status == 0`).

**Remaining:** U06 (P3.8–P3.10).

### 2026-08-05 — U04 P3.4 review-composition graph builder (worker)

**Done:** Implemented plan §5 P3.4 only.

- **Builder:** `EvaluationParticipantGraphBuilder` injects
  `CommitmentRepositoryPort` (not `CommitmentQueryCase`); drops
  `CoordinationRepositoryPort`. `build` derives `everAck` /
  `current` via `everAcknowledged` / `hasCurrentStake` on
  `eventsByUser`; roles `committer` vs `formerCommitter`; former
  summaries/hints append ` — participation ended`; forwarders computed
  over `everAck`; offer `message`/`createdAt` from `fetchAllByBeaconId`.
- **Tests:** new `evaluation_participant_graph_builder_test.dart` (5
  scenarios: former after 30h withdraw, grace withdraw absent, active
  committer regression, participation-ended suffix, forwarder to former).
- **Fixture updates:** `evaluation_case_test.dart` beaconClose groups now
  seed `RecordingCommitmentRepository` instead of coordination response
  map; removed `_SingleCommitterCoordinationRepo` (orphaned by P3.4).
  `evaluation_graph_test_repos.dart` adds `acknowledgedCommitterCommitmentRepo`,
  configurable help-offer/forward repos, `fetchAllByBeaconId` on empty stub.

**Test assertion updates (journal record):** `evaluation_case_test.dart`
beaconClose paths that previously relied on `_SingleCommitterCoordinationRepo`
+ active-offer intersection now require acknowledged commitment events —
same product behavior (active acknowledged helper opens review window),
different data source aligned with P3.4.

**Tests run (all passed):**
- `cd packages/server && dart run build_runner build -d`
- `cd packages/server && dart test -x pg` → 1221/1221 green (+5 new)
- `cd packages/tentura_lints && dart test` → 18/18 green
- `./scripts/check-custom-lints.sh packages/server` → 0 custom lint issues

**Decisions:** `requiresReviewWindow` in `EvaluationCase.beaconClose` still
counts only `committer` role (not `formerCommitter`) — P3.5 scope (U05).
Former committers are included in review participant scaffolding and
visibility via P3.3 rules.

**Remaining:** U05 (P3.5+P3.6+P3.7).

### 2026-08-05 — U01 review (orchestrator)

**Verdict: ACCEPTED.** Independently re-ran `dart test test/domain/commitment/
commitment_state_test.dart` (16/16 green) and `dart test -x pg` (1200/1200
green, no regressions) on the worker's HEAD. Inspected `m0139.dart` against
plan §3 step-by-step — matches exactly, including backfill ordering (8a before
9-11a). Inspected `commitment_state.dart`, `commitment_repository.dart`,
`commitment_query_case.dart` — match plan §1.3-§1.5 signatures and semantics
(self-sorting predicates, `customInsert` without `seq`, transactional
projection update, exactly 4 query-case methods, no `hasMaterialRoomWork`).
Confirmed `HelpOfferRepositoryPort.fetchAllByBeaconId` and
`HelpOfferEntity.isActive` exist as used. No pre-existing untracked files were
touched. Proceeding to U02.

### 2026-08-05 — U02 review (orchestrator)

**Verdict: ACCEPTED.** Independently re-ran `dart test -x pg` (1211/1211
green), `tentura_lints dart test` (18/18), `check-custom-lints.sh
packages/server` (0/0 baseline). Inspected diffs for `help_offer_case.dart`,
`coordination_case.dart`, `user_block_case.dart` line by line against plan §4:
`offerHelp`/`withdraw` write points match; `_recordResponseCommitmentEvents`
correctly implements the acknowledged/softened branch plus the
removeFromRoom/inviteToRoom→readmitted branch in the right precedence;
idempotence helpers (`_recordAcknowledgedIfTransition` etc.) check current
state before writing, matching the write-rule box in §4. Confirmed
`deleteForCommit` has zero remaining source references (only stale compiled
binaries matched). Confirmed the `_coordination` field removed from
`UserBlockCase` had no other use before deletion. Proceeding to U03.

### 2026-08-05 — U03 review (orchestrator)

**Verdict: ACCEPTED.** Independently re-ran `dart test -x pg` (1216/1216
green) and `check-custom-lints.sh packages/server` (0/0 baseline). Confirmed
`BeaconCase`'s `CoordinationRepositoryPort`/`HelpOfferRepositoryPort` deps were
only used by the two old committer-detection blocks now replaced — removing
them did not strand other functionality (clean diff, no leftover references).
Confirmed `formerCommitter(3)` was appended (not inserted/reordered) and
`fromDb` explicitly maps all four values. Confirmed all four P3.3 edit sites
match plan §5 point-for-point, including the if-chain in
`buildEvaluationVisibility` (the one the compiler wouldn't have caught).
Proceeding to U04.

### 2026-08-05 — U04 review (orchestrator)

**Verdict: ACCEPTED.** Independently re-ran `dart test -x pg` (1221/1221
green) and `check-custom-lints.sh packages/server` (0/0 baseline). Inspected
the full diff of `evaluation_participant_graph_builder.dart`: injects
`CommitmentRepositoryPort` directly (not `CommitmentQueryCase` — correct, avoids
case→case at same order), drops `CoordinationRepositoryPort` (confirmed it was
only used for the now-superseded `coordinationResponseTypeByOfferUserId` call,
no other use in the file); `everAck`/`current` computed from
`eventsByUser`/`everAcknowledged`/`hasCurrentStake`; role assignment,
`participation ended` suffix on both summary and hint, forwarder computation
over `everAck`, and `fetchAllByBeaconId` (not the active-only fetch) all match
plan §5 P3.4 exactly. Test-fixture rewiring in `evaluation_case_test.dart`
(coordination-response fixtures → `RecordingCommitmentRepository` events) is a
data-source change with equivalent asserted behavior, not a weakened
assertion. Proceeding to U09 (P8.1) next per the manifest's dependency
resequencing — it only needs `CommitmentQueryCase.everAcknowledgedUserIds`,
already stable since U01, and unblocks U07 (P3.11) sooner. U05/U06/U07/U08
follow after.

### 2026-08-05 — U09 P8.1 server display-status gate fields (worker)

**Done:** Implemented plan §10 P8.1 only (server-side; no client changes).

- **Entity:** `BeaconDisplayStatus` — `canCancel`, `canDelete`,
  `everAcknowledgedCommitterCount` (defaults false/false/0).
- **Use case:** `BeaconDisplayCase` injects `CommitmentQueryCase`; computes
  fields only when `tier == coordination && viewerId == author.id`; formulas
  mirror `BeaconCase.deleteById` / cancel gates via
  `everAcknowledgedUserIds` (`canDelete` uses draft OR empty ever-ack, not
  `status != draft &&`).
- **GraphQL:** `gqlTypeBeaconDisplayStatus` + `beaconDisplayStatusToGqlMap`
  expose all three non-null fields.
- **Tests:** extended `beacon_display_case_test.dart` — author with/without
  acknowledged history, draft-author `canDelete` regression, non-author steward
  gets false/0; uses `RecordingCommitmentRepository` + `CommitmentQueryCase`.

**Tests run (all passed):**
- `cd packages/server && dart run build_runner build -d`
- `cd packages/server && dart test -x pg` → 1225/1225 green (+4 new)
- `cd packages/tentura_lints && dart test` → 18/18 green
- `./scripts/check-custom-lints.sh packages/server` → 0 custom lint issues

**Commits (2, not pushed):**
- `96b508a3` feat(commitment): P8.1 — server display-status gate fields and computation
- `081fc972` feat(commitment): P8.1 — expose display-status gate fields in GraphQL

**Decisions:** `everAcknowledgedUserIds` (not `everHadCommitter`) used per plan
snippet; equivalent for gate booleans. `isAuthor` checked inside author-coordination
branch per plan literal. DI regen updated local `di.config.dart` (gitignored).

**Remaining:** U05 (P3.5+P3.6+P3.7) — orchestrator resequenced U09 ahead of
remaining P3 sub-units; U07 (P3.11) can now consume `everAcknowledgedCommitterCount`
once P8.2 client wiring lands in U15.

### 2026-08-05 — U09 review (orchestrator)

**Verdict: ACCEPTED.** Independently re-ran `dart test -x pg` (1225/1225
green) and `check-custom-lints.sh packages/server` (0/0 baseline). Read the
live `BeaconCase.deleteById` (lines ~827-857) to confirm the exact shape the
formula must mirror: draft branch hard-deletes and returns unconditionally
BEFORE the `everHadCommitter` gate. Confirmed `canDelete = isAuthor &&
(status == draft || everAck.isEmpty)` in `BeaconDisplayCase` matches this
precisely — the earlier-plan-draft bug (`status != draft && …`, which would
have blocked authors from deleting their own drafts) was avoided. Fields
correctly gated on `tier == coordination && viewerId == author.id`, zeroed
otherwise. GraphQL plumbing (`gqlTypeBeaconDisplayStatus` +
`beaconDisplayStatusToGqlMap`) exposes all three fields non-null. Also
deduplicated an accidental duplicate journal section (worker had appended
its checkpoint twice — harmless doc-only glitch, no code impact). Proceeding
to U05 (P3.5-P3.7).

### 2026-08-05 — U05 review (orchestrator)

**Verdict: ACCEPTED.** Independently re-ran `dart test -x pg` (1230/1230
green) and `check-custom-lints.sh packages/server` (0/0 baseline). Inspected
`beaconClose`: gate now `everHadCommitter`, mismatch still throws
`closeBranchConflict` before any mutation, `_recordUnansweredAtCloseOffers`
runs before the status transition and correctly filters `isActive &&
offerKind == 0 && !everAcknowledged`. Inspected `reopenFromReview`: limit
check before mutation, `incrementReviewReopenCount` after, both inside the
existing `runInBeaconStateTransaction` (row-locked, so the read-then-write
increment is safe despite not being a single SQL statement). `_canCloseNow`
confirmed unchanged and still excludes roles 2/3 from blocking, with a new
regression test pinning it down. Note: the worker's own journal checkpoint
landed out of chronological order (inserted mid-file instead of appended at
the end) — content is correct, only the ordering is odd; left as-is since
git commit history is the authoritative sequence record, not worth a
disruptive file rewrite. Proceeding to U06 (P3.8-P3.10).

### 2026-08-05 — U06 P3.8+P3.9+P3.10 withdraw, downgrade, admission invariant (worker)

**Done:** Implemented plan §5 P3.8–P3.10 only (no P3.11 client Close alignment, no P3.12 suite).

- **P3.8:** `allowsBeaconWithdraw` / `allowsWithdrawWhileHelpOffered` now gate on
  `status.isOpenFamily` (withdraw forbidden in Wrapping up / reviewOpen).
  Updated `docs/before-response-terminal-tombstone.md` §Withdraw — non-open-family
  tombstone branch documented as block-cleanup-only for user withdraw.
- **P3.9:** Appended `commitmentAlreadyAcknowledged` to
  `HelpOfferCoordinationExceptionCode` (end of enum). `setCoordinationResponse`
  and `declineHelpOffer` throw before mutation when downgrading/declining an
  ever-acknowledged pair. `alreadyAdmitted` enum value retained; call site removed.
- **P3.10:** Appended `admissionRequiresAcknowledgement`. `setCoordinationResponse`
  rejects `inviteToRoom == true` with non-acknowledging `responseType` (check
  ordered before P3.9 downgrade guard). Client: `CoordinationResponseType.allowsInviteToRoom`
  + cubit strips `inviteToRoom` for non-acknowledging responses before API call.

**Tests run (all passed):**
- `cd packages/server && dart test -x pg` → 1234/1234 green (+4 new)
- `cd packages/tentura_lints && dart test` → 18/18 green
- `./scripts/check-custom-lints.sh packages/server` → 0 custom lint issues
- `./scripts/check-custom-lints.sh packages/client` → within baseline
- `cd packages/client && flutter test` → 1647 passed, 14 skipped

**Commits (6, not pushed):**
- `1063c788` feat(commitment): P3.8 — forbid withdraw during Wrapping up
- `66247da9` feat(commitment): P3.9 — forbid response downgrade after acknowledgement
- `e3d9484e` feat(commitment): P3.10 — room admission requires acknowledgement (server)
- `88de3ee8` feat(commitment): P3.10 — strip invite-to-room for non-acknowledging responses (client)
- `805a1e06` fix(commitment): restore beacon_fact_card import in admission matrix test

**Decisions:** No coordination-response picker widget exists in client (removed in
prior admit/decline simplification); P3.10 UI guard lives in
`BeaconViewCubit.setCoordinationResponse` + `CoordinationResponseType.allowsInviteToRoom`.
`declineHelpOffer` reuses pre-fetched `hadAcknowledged` snapshot for the throw
(no extra `findParticipant` call). Client version bumped `5.6.36` → `5.6.37`.

**Remaining:** U07 (P3.11) client truth alignment for Close; U08 (P3.12) gate-scenario suite.

### 2026-08-05 — U06 review (orchestrator)

**Verdict: ACCEPTED.** Independently re-ran `dart test -x pg` (1234/1234
green), `check-custom-lints.sh` server (0/0) and client (112/112, matches
baseline file exactly), and full `flutter test` (1647 passed, 14 skipped, no
regressions). Confirmed `HelpOfferCoordinationExceptionCode` has both new
values appended strictly at the end (`alreadyAdmitted` retained, unused but
not deleted), no reordering. Confirmed `setCoordinationResponse`'s check
order matches the plan exactly: author → status → responseType validity →
offer activity → P3.10 admission invariant → P3.9 downgrade guard → write.
Confirmed the client guard (`CoordinationResponseType.
allowsInviteToRoomForResponseType` + `effectiveInviteToRoom` in
`BeaconViewCubit`) makes the server error practically unreachable through
normal UI flow. Self-corrected worker mistake (stray import removal, fixed
in a follow-up commit) is a non-issue — final state is clean. Proceeding to
U07 (P3.11) — the release-blocking client truth-alignment unit; both of its
dependencies (P3.5's close-gate switch and P8.1's
`everAcknowledgedCommitterCount`) are now in place.

### 2026-08-05 — U07 P3.11 client truth alignment for Close (worker)

**Done:** Implemented plan §5 P3.11 points 1–4 (P3.11.5 / `kDefaultMinClientVersion`
deferred to U10 CORE VERIFY per instructions).

- **P3.11.1:** `HelpOfferWithCoordinationRow` + `CoordinationRepository` +
  GraphQL map expose `stakeState`/`offerKind` from `beacon_help_offer`.
- **P3.11.2:** `CommitmentStakeState` enum (`fromInt` forward-compat); threaded
  through client schema/query, `CoordinationRepository`, `TimelineHelpOffer`,
  `BeaconViewCubit` mapper.
- **P3.11.3:** `helpOfferIsCommitter` → `stakeState == acknowledged`;
  `beaconStateHasCommitters` prefers `displayStatus.everAcknowledgedCommitterCount`;
  `expectedRequiresReviewWindowForState` returns server DTO value (`null` when
  DTO not loaded → Close disabled).
- **P3.11.4:** Client `BeaconDisplayStatusDto` + query now include
  `canCancel`/`canDelete`/`everAcknowledgedCommitterCount` (P8.2 data plumbing
  pulled forward); fetched in beacon view + My Work enrichment; My Work close
  uses DTO counter (disabled until loaded); beacon-view close flows gated on
  `closeReviewWindowExpectationKnown`.

**Tests run (all passed):**
- `cd packages/server && dart test -x pg` → 1236/1236 green (+2 new)
- `cd packages/client && dart run build_runner build -d`
- `cd packages/client && flutter test` → 1652 passed, 14 skipped
- `cd packages/tentura_lints && dart test` → 18/18 green
- `./scripts/check-custom-lints.sh packages/server` → 0/0
- `./scripts/check-custom-lints.sh packages/client` → 112/112 (baseline held)

**Commits (6, not pushed):**
- `303b0f89` feat(commitment): P3.11 — server stakeState/offerKind on help offer coordination row
- `70318368` feat(commitment): P3.11 — client CommitmentStakeState and TimelineHelpOffer wiring
- `5dffdcfa` feat(commitment): P3.11 — participation truth via stakeState for committer checks
- `4f0150ac` feat(commitment): P3.11 — wire everAcknowledgedCommitterCount for Close readiness
- `2ed2db5a` test(commitment): P3.11 — close review-window contract regression tests
- `75922d97` docs(commitment): U07 P3.11 journal checkpoint

**Decisions:** Client bumped `5.6.37` → `5.6.38`. `canCancel`/`canDelete` plumbed
but not wired to UI (per scope). Close sheet still uses `requiresReviewWindow ??
false` in summary for copy when DTO missing, but close actions are gated before
mutation. HUD tests updated to set `stakeState: acknowledged` on useful offers.

**Remaining:** U08 (P3.12) gate-scenario suite; U10 CORE VERIFY +
`kDefaultMinClientVersion` bump.

### 2026-08-05 — U07 review (orchestrator)

**Verdict: ACCEPTED.** This was the release-blocking unit; reviewed with extra
care. Independently re-ran `dart test -x pg` (1236/1236 green),
`check-custom-lints.sh` server (0/0) and client (112/112, baseline held), and
full client `flutter test` (1652 passed, 14 skipped, no regressions).

Traced the server field wiring end to end: `row` in
`CoordinationRepository.helpOffersWithCoordination` is the full Drift-managed
`BeaconHelpOffers` row (all table columns available since U01, including
`stakeState`/`offerKind`) — not a hand-written SQL projection that could have
silently omitted the new columns. Confirmed `gqlTypeHelpOfferWithCoordinationRow`
and the DTO map expose both fields.

Traced the client gate logic: `expectedRequiresReviewWindowForState` now
returns `bool?` (`null` when `displayStatus` hasn't loaded), and BOTH call
sites that actually trigger the close mutation
(`beacon_view_status_bottom_sheet.dart`, `beacon_view_app_bar_overflow.dart`)
guard on `closeReviewWindowExpectationKnown` before proceeding — the "disabled
until DTO loaded" requirement is real, not just documented. My Work's
`myWorkCloseBeaconEnabled`/`myWorkExpectedRequiresReviewWindow` mirror this.

Investigated the worker's flagged "Unresolved decisions" item
(`hasSuccessfulHelpOfferResult`/`helpOfferRowSettled` still read
`coordinationResponse` directly): traced `computeClosureReadiness`'s actual
call chain (`closeHardGate`, `hasClosureBlockingState`,
`hasSuccessfulHelpOfferResult`, `allRelevantHelpOffersSettled`) and confirmed
none of it routes through `helpOfferIsCommitter`/`beaconStateHasCommitters` in
the live code — this is a separate CTA-priority/summary-copy heuristic, not
the hard gate that blocks the close mutation (that gate — the one this unit
was released-blocking for — is correctly fixed). The plan's claim that the
one-line `helpOfferIsCommitter` fix "cascades" to `computeClosureReadiness` is
stale relative to current code structure; the worker correctly deferred to
live code over plan prose and flagged the discrepancy rather than either
silently doing nothing or scope-creeping into an unrelated UX heuristic. Left
as a known minor gap (CTA-priority copy may lag participation truth in edge
cases; does not cause `closeBranchConflict` or any incorrect gate decision).

Spot-checked the new regression tests in `beacon_closure_readiness_test.dart`
— `helpOfferIsCommitter` group and `expectedRequiresReviewWindowForState`
group both contain exactly the scenarios the plan calls for (released/exited
stake not committer despite stale `useful` response; accept→withdraw uses
server counter; null when DTO not loaded).

Proceeding to U08 (P3.12 — the full 18-scenario gate test suite), which
exercises everything U01-U07 have built as an integration check before the
core-verify unit.

### 2026-08-05 — U08 P3.12 gate-scenario integration suite (worker)

**Done:** Implemented plan §5 P3.12 — all 18 numbered scenarios as individual
`test(...)` cases in `commitment_gates_test.dart`, grouped by gate/mechanism.

- **Harness:** `test/support/commitment_gates_harness.dart` wires real
  `HelpOfferCase`, `CoordinationCase`, `BeaconCase`, `EvaluationCase`, and
  `CommitmentQueryCase` against `RecordingCommitmentRepository` (clock-aware),
  `InMemoryHelpOfferRepository`, and `MutableBeaconRepository`. Coordination
  row mutations remain Mockito stubs (established U02 pattern); commitment
  truth and gate predicates exercise production code end-to-end.
- **Clock:** Extended `RecordingCommitmentRepository` with `advanceClock` /
  `setClock` so grace-period scenarios (4 vs 3/5/10) drive real
  `HelpOfferCase.withdraw` timestamps.
- **Scenarios 1–18:** Cancel/Delete gates (1–6), coordination invariants
  (7–9), Close + review composition (10–11), closeNow (12–13), reopen limit
  (14), withdraw in reviewOpen (15), D13 release→re-ack (16), P3.11 Close
  branch alignment + visibility (17–18).
- **Defects found:** none — all 18 scenarios green against existing P3.1–P3.11
  code without production changes.

**Tests run (all passed):**
- `cd packages/server && dart test test/domain/use_case/commitment_gates_test.dart` → 18/18
- `cd packages/server && dart test -x pg` → 1254/1254 green (+18 new)
- `cd packages/tentura_lints && dart test` → 18/18 green
- `./scripts/check-custom-lints.sh packages/server` → 0/0 baseline

**Commits (1, not pushed):**
- `4a94ca81` test(commitment): P3.12 — 18-scenario gate integration suite (includes journal checkpoint)

**Remaining:** U10 CORE VERIFY + `kDefaultMinClientVersion` bump.

### 2026-08-05 — U08 review (orchestrator)

**Verdict: ACCEPTED.** Independently re-ran the new suite
(`dart test test/domain/use_case/commitment_gates_test.dart` → 18/18) and the
full non-pg server suite (1254/1254 green). Confirmed all 18 scenarios are
present as individually named `test(...)` cases matching the plan's table
one-for-one. Spot-checked scenario 16 (D13 release→re-acknowledge
reversibility) in full: asserts both `currentStakeIsAcknowledged() == true`
AND that the event log contains BOTH `releasedByAuthor` and the new
`acknowledged` event — correctly tests this as expected reversible behavior,
not a bug. Spot-checked scenario 17 (the P3.11 close-branch-alignment
regression) — drives `beaconClose` with `expectedRequiresReviewWindow: true`
(the value the fixed client would now send) through the real
`EvaluationCase` and asserts it completes without `closeBranchConflict` and
lands in `reviewOpen`. Notable: the worker reported (and I have no reason to
doubt, given how thoroughly P3.1-P3.11 were each independently verified)
**zero defects found** — all 18 scenarios passed against the existing
codebase with no production-code changes required. This is a meaningful
positive signal: seven independently-reviewed units compose correctly as an
integrated whole.

This closes out phase P3 in full (P3.1 through P3.12). Combined with U01/P1,
U02/P2, and U09/P8.1, every piece of the plan's "core" release boundary
(§13: P1+P2+P3 incl. P3.11+P8.1) is now implemented and individually
reviewed. Proceeding to U10 — the core-verify unit: run the full plan §12.2
verify matrix as an integrated whole, plus the `kDefaultMinClientVersion`
bump (§12.3) that was deliberately deferred by U07 to this point.
