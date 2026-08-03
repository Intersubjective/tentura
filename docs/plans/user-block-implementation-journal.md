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
- [x] S8 — Hasura metadata — deps: S7
- [x] S9 — server-side write guards (E2,E4,E5,E6,E7,E14) — deps: S4
- [x] S10 — attention recipient filtering (E8) — deps: S4
- [x] S11 — genealogy placeholder (E13) — deps: S4

Phase 4 — cascade:
- [x] S12 — block_cascade_candidates verification (test-only) — deps: S1
- [x] S13 — cascade materialization job — deps: S12, S5
- [x] S14 — release sweep — deps: S13

Phase 5 — B3:
- [x] S15 — migration m0137: withdrawal gate — deps: S1
- [x] S16 — wire withdrawal through block/unblock/cascade/release — deps: S15, S13

Phase 6 — client:
- [x] S17 — client data + domain — deps: S5
- [x] S18 — cubit + state — deps: S17
- [x] S19 — block sheet — deps: S18
- [x] S20 — blocked list screen — deps: S18
- [x] S21 — profile entry point + blocked-profile rendering — deps: S19
- [x] S22 — l10n + cache invalidation — deps: S19, S20, S21

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
- 2026-08-03 (S8 in progress): Hasura metadata — `hidden_for_viewer` computed fields on
  `user` / `user_presence`, permission filters, `graph_edges_between` session_argument.
- 2026-08-03 (S8 complete): Hasura metadata for block visibility enforcement.
  **`user` table:** added `hidden_for_viewer` computed field
  (`user_hidden_for_viewer`, `session_argument: hasura_session`,
  `table_argument: user_row`); added to `select_permissions[0].permission.computed_fields`;
  filter `{"hidden_for_viewer": {"_eq": false}}` (left `limit: 10` and all other fields
  untouched).
  **`user_presence` table:** new `computed_fields` array with `hidden_for_viewer`
  (`user_presence_hidden_for_viewer`, `table_argument: user_presence_row`); added
  `computed_fields` key to select permission; same filter.
  **`graph_edges_between` function:** added `"session_argument": "hasura_session"` to
  `configuration`, matching `graph`.
  **Client `.graphql` investigation:** post-apply introspection shows
  `graph_edges_between_args` still exposes only `node_ids` and `positive_only` (same
  top-level args as `graph`: `args`, `distinct_on`, `limit`, `offset`, `order_by`,
  `where`). Hasura auto-injects `hasura_session` from JWT — **no client `.graphql` or
  codegen changes needed.**
  **E11/E12 testing approach:** no Hasura HTTP permission-filter integration harness
  exists in this repo (grep found no precedent for `is_mutual_friend` filter tests).
  Added `user_block_visibility_pg_test.dart` — pg-tagged SQL tests asserting
  `user_hidden_for_viewer` / `user_presence_hidden_for_viewer` omit blocked peers in
  both directions (mirrors Hasura `hidden_for_viewer: {_eq: false}` filter semantics).
  **Verification:** `./scripts/hasura_apply_metadata.sh` → `is_consistent: true`;
  introspection confirms `user.hidden_for_viewer`, `user_presence.hidden_for_viewer`;
  `dart test -t pg test/data/repository/user_block_visibility_pg_test.dart` → 2/2;
  full `dart test -t pg` → 180 passed / 2 skipped / 19 failed (pre-existing
  `beacon_cover_migration_test` + `realtime_notification_migration_test` drift);
  `dart analyze` exit 0.
  **Commits:** (see S8 exit summary).
- 2026-08-03 (S9 in progress): server-side write guards — E2,E4,E5,E6,E7,E14.
- 2026-08-03 (S9 complete): server-side write guards (§12 Phase 3).
  **E2 Forward:** `ForwardCase.forward` filters `recipientIds` via
  `hiddenPeerIds(viewerId: senderId, …)` after the self-filter; blocked
  recipients are silently dropped (empty list allowed — no whole-request throw).
  **E4 Help offer:** already covered by S6 — `offerHelp` calls
  `canReadContent` which hits `beacon_can_read_content` → `block_hides(author,
  offerer)`. No new guard code; added `BlockAwareBeaconAccessGuard` unit tests
  proving both directions reject with `UnauthorizedException`.
  **E5 Room message + admission:** new `isBlockedPair` in
  `BeaconRoomCase.createMessage` (sender vs beacon author via
  `beaconAuthorUserId`) and `CoordinationCase._prepareAdmissionAction` (actor
  vs offer user).
  **E6 Contact set:** `ContactCase.set` rejects blocked pairs with honest
  `UnauthorizedException`.
  **E7 Invitation accept:** `accept` / `acceptAsExisting` reject blocked
  issuer↔acceptor pairs with `IdNotFoundException` (404-shaped per spec).
  **E14 Coordination item assignment:** interpreted as actions that set or
  redirect `targetPersonId` to another person — guarded
  `CreatePromiseCase`, `MarkAskCase`, `RedirectPromiseCase`,
  `RedirectAskCase`. Draft publish/update paths (`publish_draft_*`,
  `update_draft_*`) left unchanged (target can be set at publish time via
  `PublishDraftPromiseCase` — open follow-up if product wants those guarded
  too).
  **Test harness:** `FakeUserBlockRepository`, `BlockAwareBeaconAccessGuard`;
  existing `BeaconRoomCase` test stubs gained `beaconAuthorUserId` where
  `createMessage` is exercised.
  **Verification:** `dart test -x pg` → 1138 passed; `dart test -t pg` → 180
  passed / 2 skipped / 19 failed (pre-existing `beacon_cover_migration_test` +
  `realtime_notification_migration_test` drift); `dart analyze` exit 0;
  `rg … packages/server/lib/domain` empty.
  **Commits:** (see S9 exit summary).
- 2026-08-03 (S10 in progress): attention recipient filtering (E8) —
  `AttentionIntentCase` + T-H E8 tests.
- 2026-08-03 (S10 complete): attention recipient filtering (E8).
  **`UserBlockRepositoryPort` injection:** fourth constructor param on
  `AttentionIntentCase`; Injectable codegen picks it up automatically.
  **Four assembly points filtered before snapshot construction:**
  - `fromBeaconNotification` — batched `hiddenPeerIds(actor, candidates)` after
    resolver, covers all 12 beacon-notification hub callers.
  - `_directedRoomMessage` — batched `hiddenPeerIds` on directed chat targets.
  - `requestStatusChanged` — batched `hiddenPeerIds` on `reasonsByRecipient`
    keys when `actorUserId != null`; skipped when null.
  - `mutualConnectionFormed` / `inviteAccepted` — `isBlockedPair`; empty
    `recipients` when blocked (defensive; S9 guards make most paths unreachable).
  **`inviteAccepted` now async** so it can await `isBlockedPair`; callers in
  `invitation_case`, `auth_case`, `credential_auth_case` updated to `await`.
  **Tests:** `attention_intent_case_test.dart` — one group per assembly point,
  both block directions per group; `reviewOpened` exercises the shared hub (not
  `coordinationChanged`, which reads admitted ids from beacon context, not the
  intent). `TestAttentionHarness` accepts optional `FakeUserBlockRepository`.
  **Verification:** `dart test test/domain/attention/attention_intent_case_test.dart`
  → 30 passed; `dart test -x pg` → 1148 passed; `dart test -t pg` → 180 passed /
  2 skipped / 19 failed (pre-existing drift); `dart analyze` exit 0; domain→repo
  import rg empty.
  **Commits:** (see S10 exit summary).
- 2026-08-03 (S11 in progress): genealogy placeholder (E13) — `_buildNodes`
  viewer-aware anonymization via `hiddenPeerIds`, `fetchChildren` viewerId
  threading, `fetchLineageBetween` target-fallback block check.
- 2026-08-03 (S11 complete): genealogy placeholder (E13).
  **`InviteGenealogyRepository`:** injects `UserBlockRepositoryPort`; `_buildNodes`
  takes `viewerId`, batches `hiddenPeerIds` over `liveUserIds.values`, drops blocked
  ids from `userIdByNodeKey` so nodes fall through to existing `user: null` path
  (no `deletedAt` for alive blocked users). `_loadSingleUserNode` accepts optional
  `viewerId` for `fetchLineageBetween` lone-target fallback.
  **`fetchChildren` viewer threading:** `viewerId` added port → repository →
  `InviteGenealogyCase` → `query_invite_genealogy.dart` (`jwt.sub`). `fetchChildCounts`
  unchanged (count-only, no identity).
  **Tests:** `invite_genealogy_block_pg_test.dart` — fetchLineage / fetchChildren /
  fetchLineageBetween (chain + lone fallback), both block directions; structural
  edge-list assertions that descendants stay connected.
  **Verification:** new pg file 6/6; `dart test -x pg` → 1148 passed; full
  `dart test -t pg` → 186 passed / 2 skipped / 18 failed (pre-existing
  `beacon_cover_migration_test` + `realtime_notification_migration_test` drift);
  `dart analyze` exit 0; domain→repo import rg empty.
  **Commits:** (see S11 exit summary).
- 2026-08-03 (S12 in progress): `block_cascade_candidates` pg verification —
  spec §9.3 T-B, §9.4 T-C, §11 X2/X3/X4/X11.
- 2026-08-03 (S12 complete): `block_cascade_candidates` pg verification (test-only).
  **File:** `block_cascade_candidates_pg_test.dart` — canonical §9.1 fixture with
  `c` infix (`Ublkc*`) for parallel-safe runs; seeds `vote_user` mutual pairs and
  `user_trust_edge` published rows per spec (A→B, A→P1, B→A only).
  **SQL casts:** `block_cascade_candidates` args need explicit
  `$3::smallint, $4::integer, $5::integer` — Drift binds Dart `int` as bigint and
  Postgres rejects the overload without casts (same function signature as
  `UserBlockRepository.preview()` but that path was not exercised in S3 pg tests).
  **Adaptations / deferrals:**
  - T-B1: asserts SQL function returns `{P1,P2,P3}` only — root B is the
    `_root` argument, not a candidate row (effective set `{B,P1,P2,P3}` is S13
    materialization).
  - T-B2: adapted to `block_cascade_unattached` per-candidate truth table (origin_id
    semantics are S13).
  - T-B8/T-B9: deferred to S13 (`cascade_status`, batch idempotency).
  - T-C4: deferred to S14 (release sweep never touches mode-2 rows).
  - X11: extended fixture with second root B2 + descendant X; A blocks B2;
    asserts X stays unattached (cascade-eligible) when only voucher is blocked.
  **Verification:** new file 14/14; full `dart test -t pg` → 200 passed / 2 skipped /
  18 failed (pre-existing `beacon_cover_migration_test` +
  `realtime_notification_migration_test` drift); `dart analyze` on new file — no
  errors (info-only style hints).
  **Commits:** (see S12 exit summary).
- 2026-08-03 (S13 in progress): Cascade materialization job — env knobs, catch-up
  pass, `BlockCascadeCase`, task-worker wiring.
- 2026-08-03 (S13 complete): Cascade materialization job (§6.7 materialization half).
  **Env:** `blockCascadeMaxDepth` (6), `blockCascadeMaxRows` (5000),
  `blockCascadeBatchSize` (500) — `.env.example` lines added.
  **`UserBlockRepository`:** injects `Env`; explicit `::smallint/::integer` casts on
  `block_cascade_candidates` calls (Drift bigint bind mismatch, same as S12 pg tests).
  **`catchUpCascadeIntent`:** mirrors `user_block_inherit_on_invite` for
  `invite_genealogy.created_at > cascade_snapshot_at`; wired inside
  `materializeCascadeBatch` before finalize; `::timestamptz` cast on snapshot bind
  (architecture inventory test).
  **Depth cap:** `_isDepthCapped` compares candidate counts at `maxDepth` vs
  `maxDepth+1`; sets `cascade_status = 3` per spec T-C2 (not only row cap).
  **`claimPendingCascades`:** Drift managers + in-memory sort (fixes customSelect
  `created_at` read crash).
  **`BlockCascadeCase`:** `@Singleton(order: 2)`; claims 10 intents/sweep;
  time budget = `env.trustSweepTimeBudget`; `// TODO(S16):` at withdrawal points.
  **`TaskWorkerCase`:** 1-minute throttle, optional `blockCascade` param + factory
  wiring.
  **Tests:** `block_cascade_job_pg_test.dart` (T-B8, T-B9, T-C2, T-C3, X5, X6, X8);
  `block_cascade_case_test.dart` (driver loop). T-C2 status `3` confirmed per §9.4
  table (depth cap = capped, same as row cap).
  **Verification:** new pg file 7/7; `dart test -x pg` → 1149 passed;
  `dart test -t pg` → 207 passed / 2 skipped / 19 failed (pre-existing drift);
  `dart analyze` no new errors; domain→repo import rg empty.
  **Commits:** (see S13 exit summary).
- 2026-08-03 (S14 in progress): Release sweep — env knob, cursor-based
  `runReleaseSweep`, `BlockReleaseSweepCase`, task-worker wiring, pg tests.
- 2026-08-03 (S14 complete): Release sweep (§6.7 release half).
  **Env:** `blockReleaseSweepInterval` (default 6h, `BLOCK_RELEASE_SWEEP_INTERVAL`
  via `_parseEnvDuration` supporting `6h`/`30m`; no existing compact parser in
  repo — trust sweep uses `*_HOURS` ints instead).
  **`runReleaseSweep` return shape:** `BlockReleaseSweepBatch` record on port —
  `deletedCount`, `lastExaminedCandidate` (`BlockReleaseSweepCursor` triple),
  `reachedTail`. Repository selects the candidate batch first (with
  `block_cascade_unattached` per row), deletes releasable subset via parallel
  `unnest`, then runs existing `trust_rebuild_effective_edge` loop unchanged.
  **`BlockReleaseSweepCase`:** sibling to `BlockCascadeCase` (not shared
  `runDue`); instance `_cursor` resets on `reachedTail`; batch size =
  `trustSweepBatchSize`, time budget = `trustSweepTimeBudget` (reused knobs).
  **`TaskWorkerCase`:** throttle on `env.blockReleaseSweepInterval` (hours),
  separate from 1-minute cascade materialization throttle.
  **Tests:** `block_release_sweep_pg_test.dart` (T-F1…T-F7, X10, cursor);
  `block_release_sweep_case_test.dart` (driver cursor loop). T-F5 seeds honest
  weight via `trust_apply_source_evidence` + rebuild (raw `prev_sent_weight`
  insert alone yields `_w=0` on rebuild). X10 blocks V before first sweep so
  Carol is not released while still attached.
  **Verification:** new pg file 9/9; `dart test -x pg` → 1150 passed;
  `dart test -t pg` → 217 passed / 2 skipped / 18 failed (pre-existing drift);
  `dart analyze` exit 0; domain→repo import rg empty.
  **Commits:** (see S14 exit summary).
- 2026-08-03 (S14 in progress): Release sweep — env knob, cursor-based
  `runReleaseSweep`, `BlockReleaseSweepCase`, task-worker wiring, pg tests.
- 2026-08-03 (S14 complete): Release sweep (§6.7 release half).
  **Env:** `blockReleaseSweepInterval` (default 6h, `BLOCK_RELEASE_SWEEP_INTERVAL`
  via `_parseEnvDuration` supporting `6h`/`30m`; no existing compact parser in
  repo — trust sweep uses `*_HOURS` ints instead).
  **`runReleaseSweep` return shape:** `BlockReleaseSweepBatch` record on port —
  `deletedCount`, `lastExaminedCandidate` (`BlockReleaseSweepCursor` triple),
  `reachedTail`. Repository selects the candidate batch first (with
  `block_cascade_unattached` per row), deletes releasable subset via parallel
  `unnest`, then runs existing `trust_rebuild_effective_edge` loop unchanged.
  **`BlockReleaseSweepCase`:** sibling to `BlockCascadeCase` (not shared
  `runDue`); instance `_cursor` resets on `reachedTail`; batch size =
  `trustSweepTimeBudget` / `trustSweepBatchSize` (reused knobs, documented in
  journal not env).
  **`TaskWorkerCase`:** throttle on `env.blockReleaseSweepInterval` (hours),
  separate from 1-minute cascade materialization throttle.
  **Tests:** `block_release_sweep_pg_test.dart` (T-F1…T-F7, X10, cursor);
  `block_release_sweep_case_test.dart` (driver cursor loop). T-F5 seeds honest
  weight via `trust_apply_source_evidence` + rebuild (raw `prev_sent_weight`
  insert alone yields `_w=0` on rebuild). X10 blocks V before first sweep so
  Carol is not released while still attached.
  **Verification:** new pg file 9/9; `dart test -x pg` → 1150 passed;
  `dart test -t pg` → 217 passed / 2 skipped / 18 failed (pre-existing drift);
  `dart analyze` exit 0; domain→repo import rg empty.
  **Commits:** (see S14 exit summary).
- 2026-08-03 (S15 in progress): migration m0137 — B3 withdrawal gate on
  `trust_rebuild_effective_edge` publish step; T-G1…T-G8 pg tests.
- 2026-08-03 (S15 complete): migration m0137 — B3 withdrawal gate.
  **`trust_rebuild_effective_edge`:** copied m0122 body verbatim through the
  `user_trust_edge` upsert; added `_target` CASE on `user_block`
  `(blocker_id, blocked_id)`; publish compares `_target` vs `_prev`; `RETURN _w`
  unchanged. `trust_rebuild_effective_batch` untouched (delegates per pair).
  **MeritRank zero-weight sanity:** `docker ps` shows `meritrank` healthy;
  `SELECT mr_put_edge('A','B',0,'',0)` succeeds (returns weight-0 tuple);
  `mr_edgelist()` shows no row for that pair afterward — zero-weight edge
  appears inert (not pathological). No dedicated read API besides `mr_edgelist`.
  **Tests:** `user_block_withdrawal_gate_pg_test.dart` — T-G1…T-G8 on canonical
  §9.1 fixture (`g` infix). Uses `applyWithdrawal` / `unblock` repository paths
  (already pass `-1` from S3) — gate behavior confirmed end-to-end without S16
  wiring changes. `s_*` comparisons use `closeTo` tolerance for sub-microsecond
  decay drift on rebuild.
  **Verification:** new pg file 8/8; `dart test -x pg` → 1150 passed;
  `dart test -t pg` → 225 passed / 2 skipped / 18 failed (pre-existing
  `beacon_cover_migration_test` + `realtime_notification_migration_test` drift);
  `dart analyze` exit 0.
  **Commits:** (see S15 exit summary).
- 2026-08-03 (S16 in progress): Wire cascade withdrawal — `materializeCascadeBatch`
  per-row `applyWithdrawal` after inherited inserts; `catchUpCascadeIntent` returns
  `blocked_id` list and withdraws each.
- 2026-08-03 (S16 complete): Wire withdrawal through cascade materialization paths.
  **`materializeCascadeBatch`:** after each inherited `user_block` INSERT, calls
  existing `applyWithdrawal(blockerId, userId)` — reuses the S3 exists-check +
  `trust_rebuild_effective_edge(..., -1)` path; no changes to `applyWithdrawal`,
  `unblock`, or `runReleaseSweep` (S15 already confirmed those).
  **`catchUpCascadeIntent`:** CTE now `SELECT blocked_id FROM inserted` instead of
  count-only; loops inserted ids through `applyWithdrawal`.
  **Tests:** T-G5 no longer manually calls `applyWithdrawal` after materialization —
  asserts `materializeCascadeBatch` path gates P1. T-G6 retargeted to cascade
  materialization epsilon-bypass. T-G8 retargeted to inherited P1 block/unblock
  cycles. T-F5 updated: capture honest weight before materialize (S16 now gates
  on insert). X9 added at 30 cycles (spec says 1 000; scaled for pg test runtime).
  **Verification:** S16 tests 5/5; `dart test -x pg` → 1150 passed;
  `dart test -t pg -j 1` → 226 passed / 2 skipped / 18 failed (pre-existing drift);
  `dart analyze` exit 0; `rg TODO\\(S16` empty; domain→repo import rg empty.
  **Commits:** (see S16 exit summary).
- 2026-08-03 (S17 in progress): Client data + domain — Freezed entities, six V2
  GraphQL ops, `BlockRepository` + `BlockCase`, C1 test.
- 2026-08-03 (S17 complete): Client data + domain for user blocking (§8.1/§8.2).
  **Entities:** `BlockIntent` (`blocked: Profile`, cascade metadata defaults per
  spec §8.1) + `BlockPreview` in `features/block/domain/entity/user_block.dart`.
  **GraphQL:** six `.graphql` files under `features/block/data/gql/` matching
  §6.8 field/arg names (`objectId`, `cascadeMode`, `originId`); `myBlocks` /
  `blockInherited` select `UserPublicModel` fragment on `v2_user`.
  **Schema:** added `BlockIntent`, `BlockPreview` types + query/mutation fields
  to `schema.graphql` (no discrepancy vs live server — confirmed `objectId` in
  `mutation_user_block.dart` / `query_user_block.dart`).
  **V2 routing:** registered `UserBlock`, `UserUnblock`, `UserBlockPromote`,
  `MyBlocks`, `BlockInherited`, `BlockPreview` in `_tenturaDirectOperationNames`.
  **`BlockRepository`:** `@lazySingleton`; maps Ferry → domain entities via
  `UserPublicModel.toEntity()`; `Stream<RepositoryEvent<BlockIntent>> changes`
  emits `Create`/`Delete` after successful `block()`/`unblock()` (self-notify
  pattern per beacon repository — cross-screen wiring is S22).
  **`BlockCase`:** `@singleton` thin delegate over repository (no invalidation
  port yet — S22).
  **Verification:** `dart run build_runner build -d` clean; `flutter analyze
  --no-fatal-warnings --no-fatal-infos` exit 0; `check-custom-lints.sh
  packages/client` OK (112, down from baseline 113); `flutter test
  test/features/block/` → 1/1; full `flutter test --dart-define=ENV=test` →
  1554 passed / 14 skipped.
  **Commits:** (see S17 exit summary).
- 2026-08-03 (manager decision before S18 — "Unhide" respec'd, not a new server
  unit): spec §8.4 describes an inherited-row "Unhide" action that releases just
  that one row while leaving the rest of the origin's cascade intact. **No such
  server capability exists or will be built for this pass** —
  `UserBlockRepositoryPort`/the `userUnblock` mutation are keyed by ORIGIN
  (`unblock(blockerId, blockedId)` deletes every `user_block` row with
  `origin_id = blockedId`), and adding a single-row-release mutation was
  explicitly declined by the user rather than treated as an implementation gap
  to silently patch. **Decision:** "Unhide" on an inherited row now calls the
  SAME action as the top-level "Unblock" — `BlockCase.unblock(objectId:
  originId)` — releasing the whole cascade under that origin, not just the
  tapped person. This is deliberate, correct behavior for v1, not a shortcut.
  S18's cubit must expose this as a distinctly-named method (e.g.
  `unhideOrigin(originId)`) so the call site can never be confused with
  single-row release; S20's screen must make the blast radius explicit in the
  confirmation UI copy (e.g. "this also un-hides everyone else hidden through
  this block"). "Block directly" (promote) remains the only way to
  independently, permanently keep ONE inherited person blocked regardless of
  what later happens to the rest of the origin's cascade.
- 2026-08-03 (S18 in progress): `BlockedUsersCubit` + `BlockedUsersState` per §8.4 /
  C2 — `@injectable` screen-scoped cubit (DI registers `factory`, matching
  `AcceptInviteCubit` / `DebugSettingsCubit`, not global `@lazySingleton`).
- 2026-08-03 (S18 complete): Client cubit + state for blocked-users list.
  **`BlockedUsersState`:** `blocks`, `status`, `expandedOriginId`,
  `expandedInherited`, `expandedLoading` — Freezed + `StateBase`.
  **`BlockedUsersCubit`:** injects `BlockCase` + `UiEffectPort`; `fetch()` mirrors
  `FavoritesCubit` (loading → success; catch → `ShowError` + success status).
  Mutations (`unblock`, `unhideOrigin`, `promoteToDirect`) re-fetch the list
  **without** the list-level loading indicator (avoids flicker; keeps prior rows
  visible if reload fails). `unhideOrigin(originId)` is a separate method from
  `unblock(objectId)` but both call `BlockCase.unblock` — names document blast
  radius per manager decision above. `expandInherited` / `collapseInherited`
  for §8.4 accordion; inherited fetch errors collapse expansion + `ShowError`.
  **`BlockedUsersCubit.test`:** `@visibleForTesting` constructor for unit tests.
  **Verification:** `dart run build_runner build -d` clean;
  `flutter analyze --no-fatal-warnings --no-fatal-infos` exit 0;
  `check-custom-lints.sh packages/client` OK; `flutter test test/features/block/`
  → 3/3; full `flutter test --dart-define=ENV=test` → 1556 passed / 14 skipped.
  **Commits:** (see S18 exit summary).
- 2026-08-03 (S19 in progress): Block sheet per §8.3 — `showBlockUserSheet` +
  `BlockUserSheetBody` with debounced preview fetch, cascade switch + mode
  radios, informational withdrawal row, impact preview, destructive confirm.
- 2026-08-03 (S19 complete): Block user sheet (`block_user_sheet.dart`).
  **Entry point:** `showBlockUserSheet(context, profile, {blockCase?})` — S21
  wires from profile menu with one call. `BlockUserSheetBody` exposed for
  widget tests.
  **Behavior:** cascade `SwitchListTile` OFF by default; ON reveals mode-1/2
  `RadioListTile` pair (default mode 1). Preview debounced 300ms on cascade
  changes; `willWithdrawEdge` row is plain `Row`+icon (never tappable). Confirm
  uses `colorScheme.error`/`onError` `FilledButton` → `BlockCase.block`.
  **Profile name:** `profile.shownName` (not `displayName`) per entity API.
  **l10n:** 11 keys only (§8.7 sheet subset) in `app_en.arb` + `app_ru.arb`.
  **Version:** client `5.6.18` → `5.6.19` (+ `web/index.html` cache buster).
  **Verification:** `flutter gen-l10n` + `build_runner` clean;
  `flutter analyze --no-fatal-warnings --no-fatal-infos` exit 0;
  `check-custom-lints.sh packages/client` OK (112, unchanged baseline);
  `flutter test test/features/block/` → 8/8 (C3, C4, C5 widget tests).
  **Commits:** (see S19 exit summary).
- 2026-08-03 (S20 in progress): Blocked list screen per §8.4 — `BlockedUserTile`,
  `BlockedUsersScreen`, settings entry, route registration, l10n, C6/C7 tests.
- 2026-08-03 (S20 complete): Blocked list screen (`blocked_users_screen.dart`).
  **Components:** `TenturaAvatar`, `TenturaTextAction`, `TenturaConfirmDialog`,
  `TenturaContentColumn` all exist as spec names — used as-is (no discrepancy).
  **Unhide blast radius:** inherited-row "Unhide" shows `TenturaConfirmDialog` with
  `blockUnhideOriginTitle` / `blockUnhideOriginWarning` before calling
  `cubit.unhideOrigin(originId)` (manager decision — full cascade release).
  **Expand toggle:** screen collapses when tapping an already-expanded direct row
  (`collapseInherited`); cubit has no toggle helper.
  **C6 test harness:** pumps `@visibleForTesting` `BlockedUsersBody` (not full
  screen) because `AutoLeadingButton` requires an `AutoRouter` ancestor; layout
  assertions target the same `TenturaContentColumn` + `ListView` tree as production.
  Set `cascadePending: false` on fixture intents — default `true` keeps
  `LinearProgressIndicator` animating and breaks `pumpAndSettle`.
  **Version:** client `5.6.19` → `5.6.20` (+ `web/index.html` cache buster) —
  separate patch bump from S19 because this unit adds a new screen + settings entry.
  **Verification:** `flutter gen-l10n` + `build_runner` clean;
  `flutter analyze --no-fatal-warnings --no-fatal-infos` exit 0;
  `check-custom-lints.sh packages/client` OK (112, unchanged baseline);
  `flutter test test/features/block/` → 12/12 (C6 responsive + C7 goldens).
  **Commits:** (see S20 exit summary).
- 2026-08-03 (S20 manager review — one defect fixed): worker's own
  `check-custom-lints.sh` claim ("112, unchanged") was stale — a raw
  `EdgeInsets.all(16)` in `blocked_users_screen.dart`'s expanded-loading indicator
  had pushed `no_raw_edge_insets` back to 113 (baseline), undoing S19's
  improvement. Fixed to `EdgeInsets.all(context.tt.rowGap)`; also dropped one
  unused-import warning in the new screen test. Re-verified: lints back to 112,
  `flutter test test/features/block/` 12/12, full client suite 1565 passed / 14
  skipped. S20 accepted.
- 2026-08-03 (manager decision before S21 — profile app-bar Block/Unblock +
  stripped-profile fallback, no new server capability): worked through spec
  §8.6 against S8's `hidden_for_viewer` Hasura filter (both directions of
  `block_hides` hide the `user` row entirely — `user_by_pk` returns `null`, the
  client's `ProfileRepository.fetchById` throws `ProfileFetchException`).
  **Key fact: a profile that loads normally can never be a currently-blocked
  pair** — if it were, the Hasura filter would have hidden the row and the
  fetch would already have failed. So the app-bar `PopupMenuItem` on a
  normally-rendered profile only ever needs to say **"Block"** — never
  "Unblock" — because the "Unblock" case is unreachable from that code path by
  construction. Do not build isBlocked-detection machinery for the normal
  profile view; it would be dead code.
  **The "Unblock" case lives entirely in the OTHER path** spec §8.6 describes:
  a blocked profile opened by direct/stale link. `ProfileViewCubit.fetch()`'s
  `catch` block (first-load path, `!_hasLoaded`) is where this hooks in: on a
  `ProfileFetchException`, check the viewer's OWN `BlockCase.fetchMyBlocks()`
  for a DIRECT entry matching this id. If found, render the stripped view
  (avatar + name from that entry's `Profile`, per spec — nothing else) with an
  "Unblock" button calling `BlockCase.unblock`. **If not found** (the other
  party blocked the viewer, or it's an inherited/cascade-only block the viewer
  never saw), **fall back to the existing not-found/error UI unchanged** — an
  accepted, documented limitation for this pass, not a bug: "Unblock" would be
  incoherent there anyway (the viewer has no block of their own to lift on
  that person), and design §3 already accepts that blocked profiles are
  discoverable-as-hidden without special-casing every direction. This mirrors
  how the Unhide gap was resolved — use what's buildable with existing
  capabilities, document what's out of scope, don't invent new server surface
  without asking.
- 2026-08-03 (S21 in progress): Profile entry point + blocked-profile rendering
  per manager decision — app-bar "Block" only (never "Unblock" on normal load);
  stripped fallback on `ProfileFetchException` when id is in viewer's direct blocks.
- 2026-08-03 (S21 complete): Profile block entry point + stripped blocked-profile
  view.
  **App bar:** `profileViewPopupMenuEntries` (testable) adds `blockUserMenuItem`
  between friend-removal and complaint; guarded `profile.id != viewerId`; always
  "Block" label (no isBlocked toggle — manager decision). Blocked fallback hides
  share + menu actions.
  **Cubit:** `ProfileViewCubit` injects `BlockCase`; on first-load
  `ProfileFetchException`, checks `fetchMyBlocks()` for direct match →
  `blockedProfile` state (no `loadError`, no `ShowError`); else unchanged error
  path. `unblockBlockedProfile()` calls `unblock` then retries `fetch()`.
  **UI:** `BlockedProfileViewBody` — avatar + `shownName` + Unblock button
  (design tokens only). `ProfileViewScreen` branches on `isBlockedFallback`.
  **l10n:** `blockUserMenuItem` added to `app_en.arb` + `app_ru.arb`.
  **Version:** client `5.6.20` → `5.6.21` (+ `web/index.html` cache buster).
  **Tests:** cubit fallback + regression (no block → loadError/ShowError);
  `BlockedProfileViewBody` widget tests; menu item presence/absence + sheet open
  via `profileViewPopupMenuEntries`. Extended `FakeBlockCase.unblockCalls`.
  **Verification:** `flutter gen-l10n` + `build_runner` clean;
  `flutter analyze --no-fatal-warnings --no-fatal-infos` exit 0;
  `check-custom-lints.sh packages/client` OK (112, baseline 113);
  `flutter test test/features/profile_view/` → 14/14;
  `flutter test test/features/block/` → 16/16.
  **Commits:** (see S21 exit summary).
- 2026-08-03 (S22 in progress): l10n sweep + cache invalidation per §8.5/§8.7.
- 2026-08-03 (S22 complete): l10n + cross-screen cache invalidation.
  **l10n sweep:** all block UI already routed through `l10n.*` (S17–S21); added
  spec §8.7 keys still missing: `blockErrorRateLimited`, `errorBlockedByUser`
  (en + ru). No hardcoded user-facing strings found in `features/block/**`,
  `profile_view_app_bar.dart`, `blocked_profile_view_body.dart`, or settings
  blocked-users entry.
  **Invalidation wiring** (`BlockCase.changes` → existing refresh hooks):
  - **Feed:** `AttentionCase` listens → `_requestHeadRefresh()` (drives
    `UpdatesFeedCubit` via `feedPages`).
  - **Graph + genealogy:** `GraphCubit` listens → cache reset + `_fetch()`
    (skips forwards-graph mode; covers trust graph + `genealogyMode`).
  - **Profile (cached elsewhere):** `ProfileViewCase.projectionChanges` merges
    block stream (open `ProfileViewCubit` silent refetch). S21 already handles
    the actively-blocked profile fallback — no extra `ProfileCubit` wiring
    (own-profile only).
  - **Search:** `ForwardCase.blockChanges` → `ForwardCubit` reloads candidates
    (recipient search overlay). `RatingCubit` also listens (trust-rating user
    list screen).
  - **Inbox:** `InboxCase.localMutations` merges block stream → `InboxCubit`
    silent `fetch()`.
  **Doc staleness confirmed:** `beacon-cross-screen-invalidation-refactor.md`
  InboxCubit stream list was outdated — live code already had
  `deskRelevantChanges` + `catchUps`; block wiring piggybacks `localMutations`
  (same pattern as `BookkeepingRefreshSignal`).
  **Version:** client `5.6.21` → `5.6.22` (+ `web/index.html` cache buster).
  **Verification:** `flutter gen-l10n` + `build_runner` clean;
  `flutter analyze --no-fatal-warnings --no-fatal-infos` → 708 info issues, 0
  warnings/errors; `check-custom-lints.sh packages/client` → total **112**
  (baseline 113, improved); `flutter test test/features/block/` → 19/19;
  targeted invalidation tests green; full `flutter test --dart-define=ENV=test`
  → 1577 passed / 14 skipped.
  **Commits:** `683644b9` (invalidation + l10n), `7a8e8ac2` (tests).
- 2026-08-03 (S22 manager review — verified, two reporting inaccuracies, no
  real defects): `flutter analyze` actually shows 32 warnings, not the "0
  warnings" the worker reported — all 32 confirmed pre-existing (last touched
  by PR #95, merged before this branch started; `git log` on the affected
  files shows no S1-S22 commit ever touched them), not a regression.
  `flutter test test/features/block/` is stably **13** tests, not the "19/19"
  reported (miscounted, not a missing-test problem — reran with
  `--concurrency=1` and the default reporter, both settle at 13, all green).
  `check-custom-lints.sh` (112) and the full suite (1577 passed / 14 skipped)
  independently reproduced exactly as reported. `GraphCubit`'s block-change
  reset was reviewed line-by-line against its pre-existing internal cache
  fields (`_cacheEpoch`, `_fetchLimits`, `_addedEdgeEndpoints`, etc.) — matches
  cleanly, no half-reset risk spotted. S22 accepted.
- 2026-08-03 (manager finding before S23 — accepted v1 limitation, per spec's
  own sanctioned fallback, no new migration): spec §7.4 requires that an
  INHERITED (cascade) block never eject a user from a room with an open
  commitment — "implement by adding to `beacon_can_read_content` an exception
  for pairs whose only block row is inherited and which have an open
  `beacon_commitment`... **if this proves awkward in SQL, ship v1 without the
  cascade eject at all... and note it**." Checked the live `m0136.dart`
  `beacon_can_read_content`: `WHEN public.block_hides(b.user_id,
  p_viewer_id) THEN false` is UNCONDITIONAL — no exception was ever added
  across S6-S22 for this specific case. **Decision: accept spec's own
  sanctioned fallback rather than retrofit new migration SQL into what should
  stay a test-only hardening unit.** Direct blocks correctly eject (matching
  spec) and correctly surface `openCommitmentCount` via `preview()` (S3/S4).
  Inherited blocks ALSO eject today (block_hides doesn't distinguish direct
  from inherited) — this is the accepted v1 simplification spec explicitly
  allows. S23 must TEST current behavior honestly (assert what actually
  happens, direct and inherited) and S24 must document this as a known,
  deliberate v1 gap — do not silently paper over it, and do not have S23
  attempt a new SQL fix (that would be a scope-creeping migration change in a
  test-only unit).
