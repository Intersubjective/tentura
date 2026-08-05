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
- [ ] U02 — P2: record facts at all write points (help_offer_case,
      coordination_case, user_block_case, remove `deleteForCommit`, P2 tests)
- [ ] U03 — P3.1+P3.2+P3.3: Cancel/Delete gates switch to `everHadCommitter`;
      `formerCommitter` role added everywhere it's exhaustively matched
- [ ] U04 — P3.4: review-composition graph builder rewritten on commitment
      events
- [ ] U05 — P3.5+P3.6+P3.7: Close review-window trigger, `unansweredAtClose`
      write, `_canCloseNow` former-committer exclusion, reopen limit
- [ ] U06 — P3.8+P3.9+P3.10: withdraw forbidden in Wrapping up, response
      downgrade forbidden after acknowledgement, room-admission-requires-
      acknowledgement invariant (+ client UI guard)
- [ ] U07 — P3.11: client truth alignment for Close (**release-blocking per
      plan**) — server `stakeState`/`offerKind` on coordination row, client
      `CommitmentStakeState`, `helpOfferIsCommitter` rewrite, My Work counter
      wiring (depends on P8.1 field `everAcknowledgedCommitterCount` — see U09)
- [ ] U08 — P3.12: full P3 gate-scenario test suite (18 scenarios) — run after
      U03–U07 land
- [ ] U09 — P8.1: server `canCancel`/`canDelete`/`everAcknowledgedCommitterCount`
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

(none yet)

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
