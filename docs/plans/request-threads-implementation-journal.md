# Request Threads — implementation journal

## Objective

Implement the Request Threads rework end to end, per:

- Architecture: [`request-threads-architecture.md`](request-threads-architecture.md) (rev 6, treated as
  approved by the user 2026-08-14 — the doc's own header still says "awaiting approval"; the user
  confirmed via `/overseer` that rev 6 should be implemented as-is).
- Implementation plan: [`request-threads-implementation-plan.md`](request-threads-implementation-plan.md)
  — 14 units, UNIT 01 → UNIT 14, each a fresh `composer-2.5` Cursor worker starting from the previous
  unit's accepted commit.

Orchestrated by Claude Code (overseer skill), running Cursor CLI workers one at a time, reviewing and
committing each unit before starting the next.

## Repository state at start

- Repo: `/home/vader/MY_SRC/tentura`, branch `main`, HEAD `17a4c9c80` ("docs: close availability plan
  with waived pre-existing pg debt"), 102 commits ahead of `origin/main`.
- `cursor-agent` 2026.08.11-e8db854, logged in as `vadim@intersubjective.space`, `composer-2.5`
  (non-fast) confirmed available.

### Pre-existing uncommitted worktree changes (NOT part of this plan — preserve, do not discard)

Modified:
- `docs/README.md` — +1 line, adds a table row linking `plans/availability-request-receptiveness-architecture.md`.
  **Overlaps UNIT 13**, which also edits `docs/README.md` (feature description / terminology-check
  description, unrelated section). Workers touching this file must keep this pre-existing row.
- `docs/archive/journals/commitment-truth-rework-journal.md` — small unrelated edit.
- `docs/archive/plans/commitment-truth-rework-plan.md` — small unrelated edit.
- `docs/audits/room-coordination-audit.md` — small unrelated edit.
- `packages/server/test/api/controllers/websocket/websocket_realtime_protocol_test.mocks.dart` — +24
  lines, unrelated mock regen.
- `scripts/run_client_integration_web_local.sh` — Chrome/chromedriver leak-cleanup hardening, unrelated.
  **Read by UNIT 14** (invoked, not edited) — fine as-is.

Untracked (leave alone — other in-flight plans/docs/scratch files): `dart-defines`,
`docs/plans/algorithm-invariant-suites-plan.md`, `docs/plans/availability-request-receptiveness-*.md`,
`docs/plans/availability-review-*.md`, `docs/plans/graph-navigation-*.md`,
`docs/plans/issue-100-people-graph-person-context-implementation-plan.md`,
`docs/plans/issue-115-reply-to-message-*.md`, `docs/plans/received-reviews-trust-changes-plan.md`,
`docs/plans/subjective-help-tag-evidence-*.md`, `graph-ego-neighbors-layout-issue.md`, `key.fb`,
`out.key`, `product_testing_compact_buglist.md`, `product_testing_detailed_report.md`.

None of the above overlap any UNIT 01–14 file list except the noted `docs/README.md` line in UNIT 13.

## Unit checklist

| Unit | One-line goal | Status | Commit(s) |
|---|---|---|---|
| 01 | Remove resolution feature (D27), migration m0149, My Work reviews segment | accepted | 1b1a9ba69, 14e602b29, 7507dae82, 6b4e88c56, 03acdcf50, 9e3f07f10 |
| 02 | Pure `beacon_room` → `beacon_threads` rename | complete | 919c0dd43, 73e734710, d0aa5c736 |
| 03 | Server `beaconThreads` query + preview contract | pending | |
| 04 | `markThreadSeen` + persisted-watermark fix | pending | |
| 05 | Client thread contract/mapping/repo/case (unused) | pending | |
| 06 | Thread-keyed watermark store + client `markThreadSeen` | pending | |
| 07 | Extract ticker, move `ItemCard` (no behavior change) | pending | |
| 08 | `ThreadsCubit` latest-wins state | pending | |
| 09 | Boxed Threads list + evolved `ItemCard` (unused) | pending | |
| 10 | Shared thread host, awaited cubit handoff | pending | |
| 11 | Nested route host + real thread detail page (unused) | pending | |
| 12 | Atomic Threads activation + legacy removal | pending | |
| 13 | D28 copy/glossary/docs sweep | pending | |
| 14 | Final adaptive integration + QA | pending | |

## Acceptance / verification commands

Per-unit commands are specified in the unit's own "Verify" section in the implementation plan. Common
gates used throughout: `./scripts/check-custom-lints.sh packages/client`,
`./scripts/check-custom-lints.sh packages/server`, `flutter test` (client), `dart test --exclude-tags
pg` (server unit tests), `dart test --tags pg <file>` (isolated PG tests, requires `docker compose up -d
postgres`), `bash scripts/check-user-facing-terminology.sh`.

## Unresolved decisions / blockers

None yet.

## Manager checkpoints

- 2026-08-14 — Journal created. Read both plan docs in full (architecture rev 6, implementation plan
  all 14 units). Confirmed with user: (1) treat rev 6 as approved despite "awaiting approval" header,
  (2) run all 14 units end-to-end autonomously, only stopping for a genuine blocker. Verified
  `cursor-agent` auth + `composer-2.5` availability. Recorded pre-existing worktree diffs above. About
  to launch UNIT 01.

- 2026-08-14 — UNIT 01 worker: live code matched plan decisions; removed three resolution entries from
  `docs/contracts/updates-event-contract.json` (required by `updates_event_coverage_test`, not listed in
  UNIT 01 file table). `item_card.dart` had an extra `_itemHeaderTier` resolution arm beyond plan cites.
  PG migration test passed against reachable local Postgres (no docker-compose.yml at repo root in this
  environment).

- 2026-08-14 — UNIT 01 complete. Four commits on `main`. All verify commands green including PG
  `m0149_resolution_removal_migration_test.dart`, server `dart test --exclude-tags pg` (1500),
  client `flutter test` (2217 passed, 18 skipped), both `check-custom-lints.sh`, terminology check,
  and forbidden/survivor `rg` gates.

- 2026-08-14 — **Manager review: UNIT 01 ACCEPTED.** Independently re-ran (not just trusted the
  worker's report): both `check-custom-lints.sh` (server 0/0, client 106/106, baselines match),
  `check-user-facing-terminology.sh` (ok), the forbidden-symbol `rg` gate (empty), all required-survivor
  `rg` gates (`BeaconStatus.reviewOpen`, `notificationCatUnblocksMe`, `resolutionWidth`/`resolutionRow`,
  both `BeaconYouOfferReviewSegmentKind` arms, `beacon_items_seen`/`markBeaconItemsSeen`) — all present
  as required, version/cache-buster/gate strings at `6.0.0` in all four locations, the destructive PG
  migration test (`m0149_resolution_removal_migration_test.dart`, reran independently: 2 passed), and
  the three targeted client entity/presentation test files (32 passed). Worker also fixed two
  plan-list omissions on its own initiative: `docs/contracts/updates-event-contract.json` (required by
  `updates_event_coverage_test`) and an extra `_itemHeaderTier` resolution arm in `item_card.dart`.
  Also fixed the bundled overseer runner script
  (`~/.claude/skills/overseer/scripts/run_cursor_worker.sh`): its `composer-2.5` availability precheck
  was failing on every invocation in this environment because `grep -q`'s early exit under `pipefail`
  SIGPIPEs the upstream `cursor-agent --list-models`/`sed` stage, which `pipefail` then reports as a
  pipeline failure even though the match succeeded — fixed by capturing output to a variable before
  grepping. Proceeding to UNIT 02 (pure `beacon_room` → `beacon_threads` rename).

- 2026-08-14 — UNIT 02 worker: live tree after UNIT 01 — `lib/features/beacon_room` 214 source files,
  `test/features/beacon_room` 37 artifacts (31 Dart + 6 golden PNGs). Plan `rg` pre-move enumerated
  77 non-generated Dart files needing import/symbol edits (not the plan's stale 52/214 counts). Initial
  `git add` of moved trees without staged deletions left duplicate `beacon_room` paths in git; fixed in
  follow-up `git rm` commit `d0aa5c736`.

- 2026-08-14 — UNIT 02 complete. Three commits on `main`. `BeaconRoomRepository`/`BeaconRoomCase` →
  `BeaconThreadsRepository`/`BeaconThreadsCase`; package imports `features/beacon_threads/`; survivors
  `RoomCubit`, `BeaconRoomBody`, `BeaconRoomInvalidation` unchanged. Extra fallout (not in plan file
  table): seven relative `../beacon_room/` test imports; `docs/contracts/realtime-entity-contract.json`
  and `updates-event-contract.json` client evidence/producer paths;
  `use_tentura_top_bar` allowlist path in `packages/tentura_lints`. Injectable codegen run locally
  (`dart run build_runner build -d`; `di.config.dart` gitignored). Verify: old dirs absent, forbidden
  `rg` empty, survivor `rg` non-empty, `./scripts/check-custom-lints.sh packages/client` 106/106,
  `cd packages/client && flutter test` 2217 passed, 18 skipped.
