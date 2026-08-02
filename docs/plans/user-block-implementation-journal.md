---
status: in-progress
kind: journal
---
# User blocking — implementation journal

**Plan source:** [`user-block-design.md`](./user-block-design.md) (rationale) +
[`user-block-implementation-spec.md`](./user-block-implementation-spec.md) (§12 has the
S1–S24 subtask manifest — read it before touching any unit).

**Repository:** `/home/vader/MY_SRC/tentura` (pub workspace: `packages/client`,
`packages/server`, `packages/tentura_lints`).

**Branch:** `feature/user-block`, created off `main` at commit `8f714f9e` (which includes
the just-merged PR #95 "Fix graph tap explore vs rollback intent" and one pre-existing
unrelated local commit `8f714f9e` "Expand graph local fan by chord constraints"). Do not
rebase or rewrite this branch's history.

**Pre-existing worktree state at branch creation (untouched, not ours to clean up):**
untracked `dart-defines`, `key.fb`, `out.key`, and two unrelated plan docs
(`docs/plans/graph-navigation-implementation-guide.md`,
`docs/plans/graph-navigation-rework-plan.md`). Leave these alone.

**Local dev stack:** postgres, hasura, meritrank, minio already running via docker compose
(`docker ps` confirms all healthy). `.env` present at repo root. `cursor-agent` authenticated,
default model `composer-2.5` confirmed current (not `-fast`).

## Scope for this run

Full plan, all 24 subtasks (S1–S24), per user decision — not just the design doc's v1
(B1+B3) scope. Cascade (S12–S14) and B3 (S15–S16) both ship in this pass, in the spec's
own subtask order (cascade before B3, matching the implementation spec's Phase 4/5 — the
design doc's "B3 ships inside v1" is about product framing, not implementation order).

## Ordered unit manifest (from spec §12)

Phase 1 — schema:
- [x] S1 — migration m0135 (tables + predicates) — no deps
- [x] S2 — Drift tables + entities — deps: S1

Phase 2 — server data & domain:
- [x] S3 — UserBlockRepositoryPort + repository — deps: S2
- [x] S4 — UserBlockCase + cleanup orchestration — deps: S3
- [x] S5 — V2 GraphQL API — deps: S4

Phase 3 — enforcement:
- [x] S6 — migration m0136 part 1: beacon wall + trigger — deps: S1
- [x] S7 — migration m0136 part 2: graph, mutual friends, computed fields — deps: S6
- [ ] S8 — Hasura metadata — deps: S7
- [ ] S9 — server-side write guards (E2,E4,E5,E6,E7,E14) — deps: S4
- [ ] S10 — attention recipient filtering (E8) — deps: S4
- [ ] S11 — genealogy placeholder (E13) — deps: S4

Phase 4 — cascade:
- [ ] S12 — block_cascade_candidates verification (test-only) — deps: S1
- [ ] S13 — cascade materialization job — deps: S12, S5
- [ ] S14 — release sweep — deps: S13

Phase 5 — B3:
- [ ] S15 — migration m0137: withdrawal gate — deps: S1
- [ ] S16 — wire withdrawal through block/unblock/cascade/release — deps: S15, S13

Phase 6 — client:
- [ ] S17 — client data + domain — deps: S5
- [ ] S18 — cubit + state — deps: S17
- [ ] S19 — block sheet — deps: S18
- [ ] S20 — blocked list screen — deps: S18
- [ ] S21 — profile entry point + blocked-profile rendering — deps: S19
- [ ] S22 — l10n + cache invalidation — deps: S19, S20, S21

Phase 7 — hardening:
- [ ] S23 — adversarial suite — deps: S16, S14
- [ ] S24 — docs + release note — deps: S23

**Execution order chosen** (respects deps, one unit at a time): S1, S2, S3, S4, S5, S6, S7,
S8, S9, S10, S11, S12, S13, S14, S15, S16, S17, S18, S19, S20, S21, S22, S23, S24.

## Acceptance / verification commands (spec §12 final gate)

```bash
cd packages/server && dart analyze && dart test -x pg && dart test -t pg
cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos
cd packages/client && flutter test --dart-define=ENV=test
cd packages/tentura_lints && dart test
./scripts/check-custom-lints.sh          # baseline: client 115, server 0 — must not grow
rg "package:tentura_server/data/repository" packages/server/lib/domain   # must be empty
```

## Unresolved decisions / blockers

(none yet)

## Checkpoints

- 2026-08-02: Journal created. Branch `feature/user-block` set up off `main`. Beginning
  S1.
- 2026-08-02 (S1 complete): Added `m0135` — `user_block`, `user_block_intent`, and
  predicates `block_hides`, `block_cascade_unattached`, `block_cascade_candidates`.
  Registered in `_migrations.dart`. Applied to shared dev DB via
  `dart run bin/utils/run_migrations_once.dart` (sourced root `.env`; harmless
  `PUBLIC`/`PRIVATE` shell noise from multiline JWT keys in `.env`). Did **not** create a
  scratch DB — dev postgres already had m0001–m0134; m0135 applied idempotently on top.
  **Schema ownership:** confirmed precedent from m0134 commit `d473957b` — migration-only
  PR, no Drift tables in same commit. S2 owns Drift registration.
  **Verification:** `\d public.user_block` shows both indexes + `user_block__no_self`;
  `SELECT public.block_hides('U1','U2')` → `false` (no user rows needed — function reads
  empty table only); server boot (`dart run bin/tentura.dart`, 25s) passed migrate + DI +
  worker start; `dart analyze` on changed migration files — info-only
  `unnecessary_raw_strings` on `r'''` SQL blocks (matches house style in m0133/m0134).
- 2026-08-02 (S2 in progress): Added Drift `UserBlocks` / `UserBlockIntents` and
  `UserBlockEntity` / `UserBlockIntentEntity` / `BlockPreviewEntity`. See final
  checkpoint below.
- 2026-08-02 (S2 complete): Drift tables + Freezed entities for user blocking.
  **Spec deviations (live repo wins):** §6.1 sample uses `dateTime()` getters;
  implemented `late final` + `customType(PgTypes.timestampWithTimezone)` like
  `MeritrankEdgeTombstones` / `AccountCredentials`. `TimestampsFields` used only
  on `UserBlockIntents` (has `updated_at`); `UserBlocks` declares `createdAt`
  alone (no `updated_at` in m0135). Added `Users` FK references + `withoutRowId`
  per house style (`UserContacts`, `VoteUsers`). `cascade_mode`/`cascade_status`
  mapped as Drift `integer()` (Postgres `smallint` — same pattern as `Beacons.status`).
  **Verification:** `dart run build_runner build -d` clean; `dart analyze` exit 0
  (2 info lints on `UserBlockIntentEntity` required-after-optional — matches spec
  §6.2 field order); server boot 25s OK; Drift `SELECT * FROM user_block` /
  `user_block_intent` round-trip OK (0 rows); `\d` column names match Drift mapping.
  **Commits:** `c456ef80` (Drift tables), `6d31b70c` (entities + journal).
- 2026-08-02 (S3 in progress): Implementing `UserBlockRepositoryPort` +
  `UserBlockRepository` + pg tests T-A1…T-A8. Will add `applyWithdrawal` to the
  port (spec §6.4; not in §6.3 interface list but required by S4).
- 2026-08-02 (S3 complete): `UserBlockRepositoryPort` + `UserBlockRepository`.
  **Port addition:** `applyWithdrawal` added to the port (spec §6.4 names it as a
  separate method for S4; omitted from §6.3 sample interface).
  **Method coverage:**
  - **Fully implemented:** `block`, `unblock`, `promoteToDirect`, `listIntents`,
    `listInherited`, `preview`, `isBlockedPair`, `hiddenPeerIds`, `applyWithdrawal`,
    `claimPendingCascades`.
  - **Partially implemented (S13/S14 finish orchestration):**
    - `materializeCascadeBatch` — single-transaction batch insert from
      `block_cascade_candidates`, status/cap updates; **missing** catch-up pass
      (§6.7 step 5), mid-run intent-abort guard (step 7), and per-batch withdrawal
      after inherited inserts (step 6 — deferred to S16 with m0137 gate).
    - `runReleaseSweep` — one bounded DELETE batch SQL from §6.7 with empty cursor;
      **missing** cursor persistence across worker passes (S14 owns sweep driver).
  **Cascade depth/row caps:** hardcoded `_cascadeMaxDepth=6`, `_cascadeMaxRows=5000`
  (S13 will wire `Env` knobs).
  **T-A5 behavior:** repository does not guard self-block; Postgres
  `user_block__no_self` CHECK rejects the transaction (test asserts `throwsA`).
  **T-A3/T-A4 beacon assertions:** skipped when m0136 `beacon_can_read_content`
  block clause absent (not yet applied on dev DB).
  **Verification:** `dart test -t pg test/data/repository/user_block_repository_pg_test.dart`
  → 7 passed, 2 skipped (m0136); `dart analyze` exit 0 on changed paths;
  `rg … packages/server/lib/domain` empty.
  **Commits:** `423be926` (port + repo), `54be9336` (pg tests), `49123b75` (journal).
- 2026-08-02 (S3 manager review — two defects fixed before accepting the unit):
  1. **`preview()`'s `openCommitmentCount` was semantically wrong.** The worker's query
     checked `beacon_participant.room_access = 3` for both users on a shared beacon —
     that's "both are admitted room participants," not "an open commitment exists," and
     it never touched `beacon_commitment` at all. Design §6.5/spec §7.4 define "open
     commitment" via `public.beacon_commitment.status = 0` (confirmed against m0024's own
     trigger logic, which checks `bc.status = 0` to mean an active commitment) between the
     beacon's author (`beacon.user_id`) and the committer (`beacon_commitment.user_id`).
     Rewrote the query to `JOIN beacon_commitment bc ON beacon` filtered on `bc.status = 0`
     and `(author,committer) = (blocker,blocked) OR (blocked,blocker)`.
  2. **`hiddenPeerIds` threw at runtime.** `Variable<List<String>>(peers)` without an
     explicit Postgres type crashes `drift_postgres` (`Unsupported type: ... _GrowableList`)
     — confirmed by direct ad-hoc reproduction against the real DB, then fixed by passing
     `PgTypes.textArray` as the second constructor arg, matching the existing precedent in
     `invite_genealogy_repository.dart:193`. Neither T-A test nor any other S3 test
     exercised this method, so the pg suite stayed green throughout — this is a reminder
     that "tests pass" only covers what the tests call.
  Both fixes verified: re-ran `dart test -t pg user_block_repository_pg_test.dart` (still
  7 passed/2 skipped) and a direct ad-hoc query against real Postgres for `hiddenPeerIds`
  (confirmed the crash pre-fix, confirmed clean 0-row result post-fix). `dart analyze`
  clean of new issues after also tidying the unused `drift/drift.dart` import and
  `combinators_ordering` info my edit touched.
  S3 accepted. Unit boundary note for S13/S14 workers: the two partially-implemented
  cascade methods noted above are unchanged by this review pass — still their job.
- 2026-08-02 (S4 in progress): `UserBlockCase` + cleanup orchestration + rate-limit
  env knob. Adding `countRecentByBlocker` to the port (not in spec §6.3 listing,
  mirrors S3's `applyWithdrawal` addition).
- 2026-08-02 (S4 complete): `UserBlockCase` + `_cleanupDirectPair` + unit tests.
  **Port addition:** `countRecentByBlocker({blockerId, window})` on
  `UserBlockRepositoryPort` — counts `user_block_intent` rows with
  `updated_at >= now() - window` (re-blocks bump `updated_at` via
  `ON CONFLICT DO UPDATE`).
  **Env:** `blockRateLimitPerDay` (default 50, `BLOCK_RATE_LIMIT_PER_DAY`);
  trailing window hardcoded to 24h in the use case (spec names only the per-day cap).
  **`getById` / `IdNotFoundException`:** live `UserRepository.getById` uses Drift
  `.getSingle()` and throws `StateError` when missing — not `IdNotFoundException`
  (that behavior exists only on the test mock). `UserBlockCase._requireUserExists`
  catches `StateError` and rethrows `IdNotFoundException` so unknown-id rejection
  is predictable for API/tests.
  **Help-offer pair correlation:** `fetchByUserId(offerer)` for each direction,
  resolve beacon author via `BeaconRepositoryPort.getBeaconById` (cached per
  cleanup pass), withdraw active offers where `offerer ≠ author` and author is the
  other party. Bypasses `HelpOfferCase` validation; `kBlockWithdrawReason = 'blocked'`
  in `domain/user_block/user_block_withdraw_reason.dart` (not added to interactive
  `kAllowedWithdrawReasonKeys` — system-initiated only).
  **Forward-edge pair correlation:** `fetchByRecipientId` per direction, filter
  `senderId` + `cancelledAt == null`, call `cancel(edgeId, senderId)` — no new port
  method needed.
  **Direct-block-only cleanup:** `_cleanupDirectPair` called only from `block()`;
  comment in source — cascade rows must never trigger cleanup.
  **Verification:** `dart test -x pg` → 1107 passed; `dart analyze` exit 0;
  `rg … packages/server/lib/domain` empty.
  **Commits:** `5f1432b5` (env + countRecentByBlocker), `8d575b0a` (UserBlockCase),
  `904a0eab` (unit tests + journal).
- 2026-08-02 (S4 remediation — §6.6 bookkeeping gap): Manager review found
  `UserBlockCase._withdrawOffersByOfferer` and `_cancelEdgesFromSenderToRecipient`
  called repository ports directly without the coordination/inbox side effects that
  `HelpOfferCase.withdraw` and `ForwardCase.cancelForward` perform after the column
  update. **Fix:** inject `CoordinationRepositoryPort` + `InboxRepositoryPort`; in
  help-offer withdrawal mirror `HelpOfferCase.withdraw` ordering
  (`deleteForCommit` → `withdraw` → post-withdraw beacon fetch →
  `upsertWatchingForSender` or `applyTombstoneAfterWithdraw`); in forward cancel add
  `markForwardCancelledForRecipient` after each `cancel`. Voluntary-cancel guards from
  `ForwardCase.cancelForward` intentionally **not** applied (block is forced cleanup).
  **Attention intent judgment:** `TransactionalAttentionCase.runAction` cannot nest
  inside `UserBlockCase`'s existing `MutatingUnitOfWorkPort.run` — nested
  `withMutatingUser` would throw actor mismatch (`blockerId` vs offerer
  `withdrawerUserId`). Wired `helpWithdrawn` via optional `AttentionIntentCase` +
  `AttentionDispatchPort.record` inside the caller-owned UoW (same pattern the port
  documents); no transaction restructure, rollback test unchanged.
  **Tests:** extended fakes to return matching active help offers / forward edges;
  three new tests assert coordination/inbox/withdraw and forward/inbox call sequences
  (open + closed beacon branches for help offers).
  **Verification:** `dart test test/domain/use_case/user_block_case_test.dart` → 9
  passed; `dart test -x pg` → 1110 passed; `dart analyze` exit 0; domain→repository
  import rg empty.
- 2026-08-02 (S5 in progress): V2 GraphQL API — mutations + queries per §6.8.
- 2026-08-02 (S5 complete): V2 GraphQL API for user blocking.
  **Writes via `UserBlockCase`:** `userBlock`, `userUnblock`, `userBlockPromote`
  (`mutation_user_block.dart`); added thin `promoteToDirect` delegate on the case
  (metadata-only, no cleanup — mirrors `unblock` UoW wrapping).
  **Reads via resolver + ports (not use case):** `myBlocks`, `blockInherited`,
  `blockPreview` (`query_user_block.dart`) inject `UserBlockRepositoryPort` +
  `UserProfileBatchLookup` directly — matches `query_forward_reasons.dart` /
  `query_coordination_item.dart` precedent for single-repo reads; enrichment
  (intent → blocked `UserPublic` profile) stays in the API layer because it is
  GraphQL-shape assembly, not domain orchestration.
  **Argument naming:** `objectId` for the blocked user (matches
  `mutation_user_vote.dart`; contacts use `subjectUserId` for a different
  semantic). `cascadeMode` optional, defaults to `0` at resolver via
  `InputFieldInt.fromArgs(args) ?? 0`.
  **`BlockIntent` enrichment:** `listIntents` supplies
  `cascadeMode`/`cascadeStatus`/`materializedCount`; resolver batch-fetches
  profiles via `userPublicRecordsByIds`; `inheritedCount` =
  `materializedCount`, `cascadePending` = status ∈ {0,1}, `cascadeCapped` =
  status == 3. Intents whose blocked user row is missing are omitted.
  **`blockInherited`:** `listInherited` + `userPublicToGqlMap` (reuses
  `gqlTypeUserPublic`, not a new type).
  **New GraphQL types:** `BlockIntent`, `BlockPreview` in `custom_types.dart`.
  **Security:** all resolvers use `getCredentials(args).sub` only — no blocker
  id argument exists; tests pass a spoof `blockerId` arg and assert the
  repository/case still receives JWT `sub`.
  **Verification:** `dart test test/api/controllers/graphql/user_block_graphql_test.dart`
  → 10 passed; `dart test -x pg` → 1120 passed; `dart analyze` exit 0;
  `rg … packages/server/lib/domain` empty.
  **Commits:** (see S5 exit summary).
- 2026-08-02 (S6 in progress): m0136 part 1 — `beacon_can_read_content` block
  clause + `user_block_inherit_on_invite` trigger on `invite_genealogy`.
- 2026-08-02 (S6 complete): m0136 part 1 landed — beacon visibility wall +
  signup inheritance trigger.
  **Live m0124 match:** confirmed `beacon_can_read_content` body matches spec §3.1
  aside from formatting; added `block_hides` as first `WHEN` only.
  **`beacon_can_read_involvement`:** unchanged — delegates to
  `beacon_can_read_content` (verified in m0124).
  **T-D test ids:** canonical §9.1 ids use a `d` infix (`Ublkdalice001`, …) and
  `pk-$id` public keys so pg tests can run parallel with
  `user_block_repository_pg_test.dart` (same Postgres, overlapping §9.1 A/B).
  **T-D materialization:** tests insert expected cascade rows directly —
  `materializeCascadeBatch` still passes `cascade_mode` as bigint to
  `block_cascade_candidates` (pre-existing Drift mismatch; S13 owns the worker).
  **T-A4b fix:** seeded reciprocal forward edges in `seedPair()` so cross-read
  assertions match m0124 involvement rules (open beacons are not world-readable).
  **Verification:** migration applied via `run_migrations_once.dart`; T-A3/T-A4b
  now run (not skipped) and pass; T-D1…T-D6 pass;
  `dart test -t pg` → 176 passed / 19 failed (pre-existing migration-contract
  failures, e.g. `primary_need_slug` in beacon_cover — unchanged by stash check);
  `dart analyze` exit 0 on changed paths.
  **Commits:** (see S6 exit summary).
- 2026-08-02 (S6 manager review — accepted, no code changes): Independently re-ran
  `dart test -t pg` on both the T-A/T-D files (15/15 pass) and the full pg suite
  (176 passed / ~18-19 failed, all in `beacon_cover_migration_test.dart` and
  `realtime_notification_migration_test.dart` — a `primary_need_slug` column
  mismatch and m0114-m0120 realtime-notification contract drift, both unrelated
  to blocking). Confirmed `m0136.dart`'s SQL is byte-identical to spec §3.1/§4.
  **Housekeeping note, not a code issue:** while trying to diff against
  pre-S6 state I ran `git stash`/`git stash pop` without a clean list check first;
  since the worktree had no local changes to stash, `pop` instead applied an
  unrelated pre-existing stash (`wip-visibility-before-attention-convergence`,
  not ours) and produced a merge conflict in unrelated beacon-visibility files.
  Recovered immediately with `git reset --hard HEAD` — confirmed via `git stash
  list` that the stash entry survived untouched and no user-block file was ever
  touched. Lesson for future units: never run bare `git stash`/`git stash pop` in
  this repo without first checking `git stash list` — there are 16 pre-existing
  stashes from other sessions/agents. Use `git worktree add` against a specific
  commit instead when a clean side-by-side diff is needed.
  S6 accepted as-is.
- 2026-08-02 (S7 in progress): m0136 part 2 — graph, `graph_edges_between`,
  `mutual_friends`, presence/user computed-field SQL. **Migration strategy:** extend
  `m0136.dart` in place (spec §12 S6/S7 both name the same file; branch-local, already
  applied on dev — append new statements per migrant append-once-applied convention).
- 2026-08-02 (S7 complete): m0136 part 2 — graph readers, mutual friends, computed
  fields (SQL only; Hasura registration is S8).
  **Migration file strategy:** extended `m0136.dart` in place (spec §12 S6/S7 both name
  the same file; branch-local, not merged). Dev DB already had `schema_version = 0136`
  from S6, so `run_migrations_once.dart` is a no-op for the new statements — applied
  part 2 manually via `docker exec postgres psql` (CREATE OR REPLACE / DROP). Fresh
  installs replay the full m0136 in one pass.
  **SQL changes:** `graph()` wraps `mr_graph` with `block_hides` on both endpoints;
  `graph_edges_between` gains `hasura_session json` (DROP 2-arg overload first);
  `mutual_friends` final SELECT filters `block_hides(alice, bob)` and per-row
  `block_hides(alice, u.id)`; added `user_presence_hidden_for_viewer` and
  `user_hidden_for_viewer`.
  **`graph_edges_between_test.dart`:** all queries pass
  `'{"x-hasura-user-id": "<viewer>"}'::json`; probe requires `pronargs = 3`.
  **New pg tests:** `user_block_graph_enforcement_pg_test.dart` — graph(),
  graph_edges_between(), mutual_friends() block filtering (T-H E9/E10 scope).
  **Verification:** manual SQL apply OK; `dart test -t pg` on changed files → 9/9;
  full `dart test -t pg` → 181 passed / 18 failed (same pre-existing
  `beacon_cover_migration_test` + `realtime_notification_migration_test` drift as S6);
  `dart analyze` exit 0.
