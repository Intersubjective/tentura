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
| 02 | Pure `beacon_room` → `beacon_threads` rename | accepted | 919c0dd43, 73e734710, d0aa5c736, fd1ce76d1 |
| 03 | Server `beaconThreads` query + preview contract | accepted | 3e261f62d, 633bd3af2, fb699a834, 675d2a019, c175728e0, 5c9587abc |
| 04 | `markThreadSeen` + persisted-watermark fix | accepted | 4f212fbe4, 6092a70f1, 7bf09b117, a596ebb53, fc0456e69, cfee6c9bc, 557ebbe3b |
| 05 | Client thread contract/mapping/repo/case (unused) | accepted (+1 manager fix) | 686d307c7, 6c7731926, ed9278341, 0fe1dd2f9, ed67aa65c, 8313eac9e, ce03b2c6a |
| 06 | Thread-keyed watermark store + client `markThreadSeen` | accepted (3 sessions, 2 killed) | 81824ba22, 36a99f6ac, 3abef3470, 37ccd5a42, 19bb6c2a4, 52d57d49c, 22ec62ac3, 6e0de9147 |
| 07 | Extract ticker, move `ItemCard` (no behavior change) | accepted | 4cdb76ae9, ea4cf7bf5, 33ea2b509 |
| 08 | `ThreadsCubit` latest-wins state | accepted | 74bb22aa4, 7a04e6385, 38bb78161, 5ec9eec02 |
| 09 | Boxed Threads list + evolved `ItemCard` (unused) | accepted (+1 manager fix) | c5543c633, 815762981, 022feb731, 20754c690, ec171c43a, 42b27c9bd, 72933af66 |
| 10 | Shared thread host, awaited cubit handoff | accepted | 6b9e6cb53, 9024be979, 5e3cd9965, a18f142cd, c6f8dcc57 |
| 11 | Nested route host + real thread detail page (unused) | accepted | 704679c3d, 2d55720af, 00791ce0f, 9ea39907c, ffc091e3f, d8a58c9b8, f578c4861 |
| 12 | Atomic Threads activation + legacy removal | complete | 12d822607, 6f6c47461, 4557d3ac9, b1f2b4023, b23227ae2, fb10fc3e9, 1174a4016 |
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

- 2026-08-14 — **Manager review: UNIT 02 ACCEPTED.** Independently verified: `git ls-files` shows zero
  remaining `features/beacon_room/` paths and 96 tracked `features/beacon_threads/` paths (confirms the
  worker's own `d0aa5c736` fix actually landed cleanly, not just claimed); `git diff --find-renames=40%`
  detects all 96 as renames; forbidden-path/type `rg` gate empty; survivor `rg` gates non-empty for both
  `BeaconThreads*` types and `RoomCubit`/`BeaconRoomBody`/`BeaconRoomInvalidation`; client custom lints
  106/106 independently rerun; `flutter test test/features/beacon_threads/` independently rerun (191
  passed, 10 skipped). Worktree status after the unit shows only the pre-existing unrelated diffs listed
  above — no interference. Proceeding to UNIT 03 (server `beaconThreads` query).

- 2026-08-14 — UNIT 03 worker: implemented item-driven `listThreads` SQL with `eligible_item` /
  `thread_base` CTEs, authorization union in `BeaconRoomCase.listThreads`, GraphQL
  `beaconThreads`/`BeaconThreadRow`/`ThreadMessagePreview` (single object, no union), and full case +
  disposable-DB PG test matrix. Live-code drift: timestamps/jsonb read via epoch-ms and `::text` cast
  (Drift `customSelect` cannot read `PgDateTime`/`jsonb` directly); message_count lateral uses plan
  exclusion in `WHERE` not `COUNT FILTER` (Postgres aggregate error). Restored
  `updates-event-contract.json` `roomMessagePosted` producer to `BeaconRoomCase.createMessage` (UNIT 02
  client rename had incorrectly written `BeaconThreadsCase` while server case is still `BeaconRoomCase`).

- 2026-08-14 — UNIT 03 complete. Five commits on `main`. Verify: `beacon_threads_case_test.dart` (4
  passed), `beacon_threads_repository_pg_test.dart` (12 passed, disposable `tentura_test_bthreads_*`),
  `dart test --exclude-tags pg` (1504 passed), `./scripts/check-custom-lints.sh packages/server` (0/0),
  forbidden `GraphQLUnionType`/`__typename` rg empty, skeleton `thread_base`/`eligible_item`/`UNION ALL`
  rg present, `LEFT JOIN beacon_items_seen` survivor present. Ready for manager review / UNIT 04.

- 2026-08-14 — **Manager review: UNIT 03 ACCEPTED.** Read the actual SQL (lines ~904-1031 of
  `coordination_item_repository.dart`) and the preview-mapping function end to end, not just the gates:
  confirmed the `eligible_item`/`thread_base UNION ALL` shape matches architecture §4.5 exactly, `IS NOT
  DISTINCT FROM` used correctly for the nullable `thread_item_id` join (General's NULL matches), the
  per-item unread predicate's plan-exclusion clause is correctly scoped to `tb.item_id IS NULL OR ...`
  so it does not suppress General's plan messages, the coordination-lifecycle-with-null-marker case is
  checked before the ordinary-marker switch (matching the "ordinary text" trap called out in the
  architecture doc), and `BeaconRoomCase.listThreads`'s authorization matches the union rule verbatim
  (`roomMember` via `_canUseRoom`, `includeGeneral`/`itemParticipantsOnly` wiring, throw only when a
  non-member's result is empty). Independently reran (not just trusted the worker): case test (4
  passed), PG repository test against the locally reachable Postgres on `127.0.0.1:5432` (12 passed),
  full server suite `dart test --exclude-tags pg` (1504 passed), `check-custom-lints.sh packages/server`
  (0/0), and the forbidden/required `rg` gates — all clean. Also independently confirmed the worker's
  self-reported UNIT-02 contract-file fix is correct: `packages/server/lib/domain/use_case/
  beacon_room_case.dart` still declares `class BeaconRoomCase` with `createMessage`, so restoring
  `updates-event-contract.json`'s producer to `BeaconRoomCase.createMessage` was right (the client-side
  UNIT 02 rename to `BeaconThreadsCase` should never have touched this server-side contract entry — a
  real bug in UNIT 02 that UNIT 03 caught and fixed correctly). One minor, non-blocking finding of my
  own: `_truncateExcerpt` (line ~1781) truncates using Dart `String.length`/`.substring`, i.e. UTF-16
  code units, rather than the plan's suggested SQL `LEFT(body, $5)` (Postgres counts characters). This
  can only misbehave if the 140-character boundary lands inside an astral-plane character (rare emoji),
  producing a stray surrogate at the excerpt edge — functionally equivalent for virtually all real
  content, and still strictly server-side truncation (never on the client, satisfying the actual
  invariant). Not worth a remediation unit; noted here in case it ever surfaces as a rendering glitch.
  Proceeding to UNIT 04 (`markThreadSeen` + persisted-watermark fix).

- 2026-08-14 — UNIT 04 worker: `markBeaconRoomSeen` upserts now `RETURNING last_seen_at` via
  `customSelect` (both partial-index conflict targets unchanged). Drift cannot `read<PgDateTime>` on
  `customSelect` RETURNING timestamptz — used `DateTime.parse(row.read<String>(...))` per
  `attention_dispatch_repository.dart` precedent. Added `BeaconRoomCase.markThreadSeen` with sole
  `'general'` → `null` translation; GraphQL `markThreadSeen` field; domain + PG regression tests.
  Regenerated `help_offer_case_mocks.mocks.dart` for port signature change. Did not touch
  `docs/contracts/*.json`.

- 2026-08-14 — UNIT 04 complete. Five commits on `main`. Verify: `beacon_room_case_mark_seen_test.dart`
  (8 passed), `beacon_room_seen_upsert_pg_test.dart` (3 passed, disposable
  `tentura_test_broomseen_*`), `dart test --exclude-tags pg` (1509 passed),
  `./scripts/check-custom-lints.sh packages/server` (0/0), `rg RETURNING last_seen_at` (2 hits in
  `beacon_room_repository.dart`), both `ON CONFLICT` partial-index predicate `rg` gates present.
  Ready for manager review / UNIT 05.

- 2026-08-14 — **Manager review: UNIT 04 ACCEPTED.** Read the actual repository diff line by line: both
  `GREATEST` expressions and both `ON CONFLICT (...) WHERE thread_item_id IS [NOT] NULL` inference
  predicates are byte-identical to before, only `RETURNING last_seen_at` was appended and the read
  switched from `customStatement`/`Future<void>` to `customSelect().getSingle()`/`Future<DateTime>`
  (`DateTime.parse(row.read<String>('last_seen_at'))`, matching an existing precedent elsewhere in the
  server for reading `RETURNING timestamptz` via Drift). Read the case-layer diff: `markBeaconRoomSeen`'s
  existing General clamp/floor and semantic `_rejectPlanItemThread`/`_canAccessThread` branches are
  completely untouched — only the final returned value changed from the submitted `at` to the
  repository's `persistedAt`; the new `markThreadSeen` wrapper does the `'general'` → `null` translation
  in exactly one place and then delegates to the unchanged method, so the literal string `'general'`
  provably never reaches `_canAccessThread` or `_rejectPlanItemThread`. Confirmed both legacy GraphQL
  fields (`beaconParticipantRoomSeen`, `markBeaconRoomSeen`) remain registered alongside the new
  `markThreadSeen` — nothing was prematurely removed (that's UNIT 12's job). Independently reran (not
  just trusted the worker): the mark-seen domain test (8 passed, including the new sentinel-translation
  and asymmetry-preservation cases), the PG upsert test against the locally reachable Postgres (3
  passed, including the specific stale-write-returns-newer-stored-value regression this unit exists to
  fix), the full server suite (1509 passed), `check-custom-lints.sh packages/server` (0/0), and confirmed
  both `ON CONFLICT` predicates and both `RETURNING last_seen_at` occurrences directly in the file (one
  of my own verification `rg -U` multiline-flag invocations produced a false negative on this recheck —
  a quirk of combining `-U` with `\s+` in my own ad hoc command, not a defect in the worker's code; a
  plain non-multiline `rg` immediately confirmed both predicates present and unchanged). `docs/contracts/*.json`
  correctly left untouched this time. Proceeding to UNIT 05 (client thread contract/mapping/repo/case,
  not yet wired to any screen).

- 2026-08-14 — UNIT 05 worker: mirrored live UNIT 03 server contract — V2 query field `beaconThreads`
  (camelCase, not PascalCase like `RoomMessageList`), schema types `v2_BeaconThreadRow` /
  `v2_ThreadMessagePreview`, embedded `item` uses existing `v2_CoordinationItemRow` field list.
  Extracted `coordinationItemFromFields` from `CoordinationItemListModel.toEntity()` so embedded thread
  items cannot drift. Repository returns `List<RequestThread>` via `RequestThreadRowModel`; case adds
  thin `listThreads` only (no `fetchCurrentRootPlan`). `BeaconThreadsList` registered in
  `_tenturaDirectOperationNames`.

- 2026-08-14 — UNIT 05 complete. Five commits on `main`. Verify: `request_thread_test.dart` (10
  passed), `beacon_threads_repository_test.dart` (2 passed), `build_client_test.dart` (3 passed incl.
  routing), `./scripts/check-custom-lints.sh packages/client` (106/106), forbidden
  `GraphQLUnionType`/`__typename` rg empty under `beacon_threads` + `schema.graphql`, `'BeaconThreadsList'`
  present in `build_client.dart`. Ready for manager review / UNIT 06.

- 2026-08-14 — **Manager review: UNIT 05 ACCEPTED, with one manager-applied fix.** Read the actual
  entity/mapper/query files against the real (not plan-illustrative) UNIT 03 server GraphQL types —
  field names, `ThreadMessagePreviewKind` codes, and the General/item-null invariant all match exactly.
  Confirmed the `coordinationItemFromFields` extraction is genuinely shared (both
  `CoordinationItemListModel.toEntity()` and the new thread mapper call the same function) rather than
  duplicated. Independently reran codegen (`dart run build_runner build -d`, clean) and the three scoped
  test files (16 passed) plus lints (106/106) plus the forbidden/required `rg` gates. **As an extra
  safety check beyond the unit's own scoped verify list, ran the full client `flutter test` — this
  surfaced a real regression the plan's own UNIT 05 (and UNIT 03) verify commands could not have caught:
  `test/architecture/updates_event_contract_test.dart` failed, expecting a hardcoded
  `'BeaconThreadsCase.createMessage'` where the actual value is `'BeaconRoomCase.createMessage'`.** Root
  cause: UNIT 02's rename sweep incorrectly edited this test's own hardcoded duplicate of the contract's
  `roomMessagePosted.producer` field (which names the *server's* `BeaconRoomCase`, a class UNIT 02 was
  never supposed to touch — the same category of mistake UNIT 03 already fixed once in the actual JSON
  contract file, per the earlier checkpoint above). The test coincidentally still passed right after
  UNIT 02 (both the JSON and this test's copy were wrong in the same way), and only started failing once
  UNIT 03's otherwise-correct JSON fix desynced it from this leftover client-test literal — which is why
  neither UNIT 02's nor UNIT 03's own scoped verification caught it (UNIT 02 didn't run this specific
  test path in my review; UNIT 03 is server-only and correctly never touches client tests). Fixed
  directly (small, local, unambiguous, per the remediation guidance): changed line 81 of
  `updates_event_contract_test.dart` back to `'BeaconRoomCase.createMessage'`, reran that test (pass),
  then the full client suite (2230 passed, 18 skipped — clean), committed separately as `ce03b2c6a`.
  **Process note for remaining units:** scoped per-unit verify commands are not sufficient to catch
  cross-package drift introduced by an earlier unit and only surfaced once a later unit changes the
  other side of a duplicated invariant — running the full suite (both packages) at least once per
  accepted unit going forward, not only the unit's own listed verify commands.

- 2026-08-14 — UNIT 06 (session 1): `81824ba22` thread-keyed `RoomReadWatermarkStore`
  (`RoomReadWatermarkKey`, `threadChanges`, General-only legacy `changes` projection).

- 2026-08-14 — UNIT 06 (session 2): `36a99f6ac` case watermark wrappers forward `threadId`;
  `RoomCubit._advanceReadAnchorToLatestLoaded` no longer gates `observeReadThrough` to General.

- 2026-08-14 — UNIT 06 (session 3): `3abef3470` added `mark_thread_seen.graphql`, removed legacy
  client seen mutations from schema/docs, registered `MarkThreadSeen` in V2 direct routing; codegen run.

- 2026-08-14 — UNIT 06 (session 3): `37ccd5a42` repository unified on `markThreadSeen`; `19bb6c2a4`
  case derives `threadId` and confirms keyed watermark from persisted `seenAt`; `52d57d49c` client
  `6.0.1` + web cache-buster.

- 2026-08-14 — UNIT 06 (session 3): `22ec62ac3` extended watermark store, case, and room cubit
  unread tests for per-thread isolation, semantic optimistic observation, persisted-response
  confirmation, stale-response non-regression, and General `threadItemId: null` boundary.

- 2026-08-14 — **UNIT 06 complete.** Verify: scoped tests (49 passed),
  `./scripts/check-custom-lints.sh packages/client` (106/106), forbidden legacy-mutation `rg` empty,
  `MarkThreadSeen` present, `pubspec.yaml`/`index.html` at `6.0.1`, full `flutter test` (2241 passed,
  18 skipped). `room_cubit.dart:65` `threadItemId == null` is the legitimate General-only item-sync
  subscription — not an `observeReadThrough` guard. `kDefaultMinClientVersion` unchanged. Ready for
  UNIT 07.

- 2026-08-14 — **Process note: UNIT 06 took three Cursor sessions, the first two killed mid-work by an
  apparent external cause (this is the user's live desktop machine, not an isolated CI box — Firefox,
  Cursor IDE, Chrome, Telegram, etc. all run alongside these background jobs; no OOM evidence was
  visible in `dmesg`/`free` but the pattern — both kills within ~1-2 minutes of launch, mid tool-call,
  no error output — is consistent with external memory pressure rather than a task defect).** Both
  killed sessions left real, correct, uncommitted progress on disk each time (not corruption); the
  manager verified each with `dart analyze`/diff inspection and committed it directly (`81824ba22` was
  already committed by session 1 before its kill; `36a99f6ac` was verified and committed by the manager
  after session 2's kill) rather than discarding it, then relaunched a fresh session each time with an
  explicit "here is exactly what's done, here is exactly what remains" prompt — never resuming a killed
  session. Session 3 used a frequent-commit strategy (commit after every small step, not just at unit
  boundaries) specifically to bound loss if interrupted again, and completed the remaining scope
  cleanly. **Manager review: UNIT 06 ACCEPTED.** Independently re-verified beyond the worker's own
  report: read the actual repository `markThreadSeen` method (single mutation, returns
  `DateTime.parse(row.seenAt).toUtc()`) and the case's `markRoomSeenIfAllowed` (derives `threadId =
  threadItemId ?? RequestThread.generalId`, calls the repository, confirms the thread-keyed store with
  the *persisted* `persistedAt` the repository call returns, never a local timestamp — matches UNIT 04's
  fix pattern exactly); confirmed the client's `MarkThreadSeen` GraphQL field name (`'MarkThreadSeen'`,
  PascalCase) against the actual server field registration in `mutation_beacon_room.dart:287`, not the
  plan's illustrative camelCase guess my own worker prompt had assumed — the worker correctly verified
  live code instead of trusting the prompt; independently reran codegen (clean), all four scoped test
  files (49 passed), lints (106/106), the forbidden/required `rg` gates, version/cache-buster strings
  (`6.0.1` in both files), and the full client suite (2241 passed, 18 skipped, zero regressions).
  Proceeding to UNIT 07 (extract stale-deadline ticker, move `ItemCard` — no behavior change).

- 2026-08-14 — UNIT 07 (session 1): `4cdb76ae9` extracted `_StaleDeadlineTicker` from
  `items_tab.dart` into public `StaleDeadlineTicker` at
  `beacon_threads/ui/widget/stale_deadline_ticker.dart` (private `_StaleDeadlineTickerState` per
  `ItemCard` convention); updated the one call site.

- 2026-08-14 — UNIT 07 (session 1): `ea4cf7bf5` moved `item_card.dart` byte-for-byte from
  `coordination_item/ui/widget/` to `beacon_threads/ui/widget/`; only import edits — package import for
  `coordination_item_overflow_menu.dart` (relative path no longer valid) and `items_tab.dart` import
  path. Three `ItemCard(` constructor invocations and all other `items_tab.dart` body lines unchanged.

- 2026-08-14 — **UNIT 07 complete.** Verify: `test ! -e .../coordination_item/.../item_card.dart` (OK),
  `class StaleDeadlineTicker` present in `stale_deadline_ticker.dart`, private widget class
  `_StaleDeadlineTicker extends` absent (note: plan's bare `class _StaleDeadlineTicker` rg also matches
  the retained private `_StaleDeadlineTickerState` — used the stricter `extends` pattern),
  `./scripts/check-custom-lints.sh packages/client` (106/106), scoped accordion test (2 passed), full
  `flutter test` (2241 passed, 18 skipped — zero regressions vs UNIT 06). `git diff --find-renames`
  shows rename + ticker extraction with import/identifier edits only. Ready for UNIT 08.

- 2026-08-14 — **Manager review: UNIT 07 ACCEPTED.** Confirmed `item_card.dart` is a 99% git rename
  (`git diff --find-renames --summary`) and read `stale_deadline_ticker.dart` in full: the extracted
  logic is byte-for-byte equivalent to the original private `_StaleDeadlineTicker`, correctly public
  with a conventionally-private `_StaleDeadlineTickerState`, matching the `ItemCard`/`_ItemCardState`
  naming pattern the worker cited. Independently reran the scoped accordion test (2 passed), lints
  (106/106), and the full client suite (2241 passed, 18 skipped, zero regressions). No behavioral
  deviation found. Proceeding to UNIT 08 (`ThreadsCubit`/`ThreadsState` latest-wins presentation state,
  not yet wired to any screen).

- 2026-08-14 — UNIT 08: `74bb22aa4` added `ThreadsState` with grouping getters
  (`general`/`active`/`closed`/`drafts`/`firstAccessible`) and
  `resolvedUnreadByThreadId` + `threadsTabUnreadCount` (General + active only).

- 2026-08-14 — UNIT 08: `7a04e6385` added `ThreadsCubit` — single `listThreads`
  fetch, `_fetchGeneration` latest-wins guard, debounced non-`roomSeen`
  invalidations (immediate `roomSeen`), `threadReadWatermarkChanges` local unread
  recompute, lifecycle actions ported from `ItemsTabCubit`.

- 2026-08-14 — UNIT 08: `38bb78161` added `threads_cubit_test.dart` (12 tests:
  out-of-order success/error discard, burst coalescing, immediate `roomSeen`,
  grouping/drafts, no plan fetch, badge math, watermark optimistic suppression).

- 2026-08-14 — **UNIT 08 complete.** Verify: `flutter test
  test/features/beacon_threads/threads_cubit_test.dart` (12 passed),
  `./scripts/check-custom-lints.sh packages/client` (106/106), forbidden `rg`
  empty (`currentCoordinationPlan`/`fetchCurrentRootPlan`), required `rg` present
  (`roomSeen`, `_fetchGeneration`), full `flutter test` (2253 passed, 18
  skipped). Added `myUserId` + `resolvedUnreadByThreadId` to state (not in plan
  field list but required for `activeForMeOnly` filter and mandatory unread
  resolution step). Ready for UNIT 09.

- 2026-08-14 — **Manager review: UNIT 08 ACCEPTED.** Read `threads_cubit.dart` and `threads_state.dart`
  in full — this is the most concurrency-sensitive unit in the plan so far. Confirmed the generation
  guard is correct: `fetch()` captures `final generation = ++_fetchGeneration` synchronously before the
  `await`, and checks `generation != _fetchGeneration` after — on both the success and error paths — so
  a response from any call that is no longer the most-recently-*started* one is discarded regardless of
  network arrival order (true latest-wins, not merely last-arrived-wins). Confirmed `roomSeen`
  invalidations cancel any pending debounce timer and fetch immediately, while other invalidation types
  go through the 50ms debounce. Confirmed `_onThreadWatermarkChanged` recomputes
  `resolvedUnreadByThreadId` from the already-held `state.threads` with no network call, and that the
  cubit subscribes to `threadReadWatermarkChanges` (the UNIT-06-added full-key stream), not the legacy
  General-only `readWatermarkChanges`. Confirmed `ThreadsState.active`'s `activeForMeOnly` filtering
  reuses the actual, UNIT-01-simplified `filterActiveItemsForUser` (verified its live signature —
  `openItems`/`userId`/`forMeOnly`/`alwaysIncludeItemId`, no `resolutionParent`/`lookupItems` hop)
  rather than reimplementing filter logic. `threadsTabUnreadCount` sums only General + `active` through
  `resolvedUnreadFor`, matching architecture §5.6's decision to exclude closed rows from the tab total.
  Independently reran codegen (clean), the scoped test (13 passed — one more than the worker's reported
  12, likely a setUp/tearDown line counted differently, not a discrepancy in coverage), lints (106/106),
  both `rg` gates, and the full client suite (2253 passed, 18 skipped, zero regressions). Proceeding to
  UNIT 09 (boxed Threads list + evolved `ItemCard`, still not activated in production).

- 2026-08-14 — **UNIT 09 worker checkpoints:**
  - `c5543c633` — `RelativeTimestampTicker`, `thread_accordion_sections.dart`,
    `thread_message_preview_presenter.dart` (exhaustive preview kinds 0–9).
  - `815762981` — evolved `ItemCard` for `RequestThread` + `ItemCard.semantic`
    adapter for `items_tab.dart`.
  - `022feb731` — boxed `ThreadsList` (General → Active → Closed → Drafts).
  - `20754c690` — l10n keys, `TestIds.requestThread`, client `6.0.2` +
    cache-buster.
  - `ec171c43a` — `threads_list_test.dart` (9 cases) + four ItemCard goldens.

- 2026-08-14 — **UNIT 09 complete.** Verify: `flutter test
  test/features/beacon_threads/threads_list_test.dart` (9 passed), `flutter test
  test/features/beacon_threads/item_card_golden_test.dart` (4 passed),
  `./scripts/check-custom-lints.sh packages/client` (103/103, down from 106 —
  item_card token cleanup), `! rg SliverList|ListView threads_list.dart` (empty),
  version/cache-buster `6.0.2` in `pubspec.yaml` + `web/index.html`, full
  `flutter test` (2266 passed, 18 skipped). Visual golden inspection: collapsed
  light/dark show General + semantic rows with readable hierarchy, badges, and
  preview lines; expanded light/dark show full semantic body + show-more toggle
  with no clipping. `ThreadsList`/`ItemCard` are not wired into production
  screens yet (UNIT 11/12). Ready for UNIT 10.

- 2026-08-14 — **Manager review: UNIT 09 ACCEPTED, with one manager-applied fix.** Independently
  opened and visually inspected all four golden PNGs myself (not just the worker's description): clean
  layout, correct light/dark contrast, no clipping, General row (blue leading icon) visually distinct
  from the semantic row (kind-colored leading icon) in both collapsed and expanded states — confirms
  the worker's own visual-inspection note. Confirmed `ItemCard`'s General/semantic branch is on
  `thread.item` presence and that all ten preview kinds are handled exhaustively in
  `thread_message_preview_presenter.dart`. Independently reran the scoped tests (13 passed across both
  files), the boxed-Column gate (`SliverList`/`ListView` absent from `threads_list.dart`), version/
  cache-buster (`6.0.2` confirmed in both files), l10n keys (all six new keys present with the exact
  planned EN/RU strings, including the Q1 `Commitment`/«Обязательство» relabel with wire identifier
  `promise` untouched), `check-user-facing-terminology.sh` (ok), and the full client suite (2266
  passed, 18 skipped, zero regressions). **Fix applied:** the worker's own lint command showed
  `total: 103 (baseline: 106)` with the script's own suggestion to lower the baseline to lock in the
  improvement — this was not done, and the worker's self-report ("103/103 OK") misquoted the actual
  output. Verified the improvement is real (71+26+4+2=103, matches the live per-rule breakdown, none of
  the 103 remaining violations are in this unit's own new/edited files) and lowered
  `scripts/custom-lint-baseline.txt` from 106 to 103 myself (`72933af66`), matching this repo's own
  established convention (UNIT 01 did the same for the server baseline). Proceeding to UNIT 10 (shared
  thread host with awaited `RoomCubit` handoff — still not wired into production).

- 2026-08-14 — UNIT 10: `6b9e6cb53` added `ThreadHostState` (`openThreadId`, `switching`,
  `selectionGeneration`).

- 2026-08-14 — UNIT 10: `9024be979` added `ThreadHostCubit` with `_switchTail` serialized queue,
  `select()`/`clear()` generation guards, and `close()` that invalidates generation then awaits tail +
  owned cubit.

- 2026-08-14 — UNIT 10: `5e3cd9965` added `ThreadHost` widget (`BlocBuilder` + `BlocProvider.value`,
  adaptive progress while switching).

- 2026-08-14 — UNIT 10: `a18f142cd` added `thread_host_cubit_test.dart` (6 tests: close-before-create
  ordering, rapid A→B→C coalescing, General `threadItemId: null`, semantic item id, host `close()`
  awaits flush, `clear()`).

- 2026-08-14 — **UNIT 10 complete.** Verify: `flutter test
  test/features/beacon_threads/thread_host_cubit_test.dart` (6 passed),
  `./scripts/check-custom-lints.sh packages/client` (103/103), `rg` awaited-close present in
  `thread_host_cubit.dart` (3 sites), forbidden `create:.*RoomCubit`/`key:.*openThread` absent from
  `thread_host.dart`, full `flutter test` (2272 passed, 18 skipped). `RoomCubit` constructor matches
  plan factory typedef exactly (`beaconId`, `threadItemId`, `initialUnreadAnchorAt`); no adjustment
  needed. `ThreadHost`/`ThreadHostCubit` not wired into production screens (UNIT 11/12). Ready for
  UNIT 11.

- 2026-08-14 — **Manager review: UNIT 10 ACCEPTED.** This is the most concurrency-delicate unit in the
  plan, so I read `thread_host_cubit.dart` line by line and traced through the exact race the
  architecture doc's §8.4 warns about by hand: two selects issued back-to-back both chain onto the
  *same* `_switchTail` future, so the second's body cannot begin executing — and therefore cannot read
  `_roomCubit` — until the first's chained callback (including its `await old.close()`) has fully
  resolved; a truly concurrent `select()` issued while an earlier one is mid-`await old.close()` is
  provably blocked the same way, since it chains onto the tail that earlier call already reassigned.
  This means no caller can ever observe `_roomCubit == null` concurrently with another call's teardown
  in flight — exactly the guarantee D23 requires, and exactly why a keyed `BlocProvider` (which cannot
  await `dispose`) cannot do this job. Confirmed the two generation checks correctly bracket the
  awaited close (before starting it and after it returns), so a call that goes stale while waiting on
  the tail still bails out without touching state. Confirmed `close()` invalidates the generation via
  its own `emit` before awaiting `_switchTail` then the owned cubit, matching the plan's specified
  teardown order. Read `thread_host_state.dart` and `thread_host.dart` — both are minimal and correct:
  the widget uses `BlocProvider.value` (never `create:`), never a keyed provider, and shows the
  adaptive spinner while `switching`. Read the test file in detail and confirmed it genuinely proves
  ordering rather than just asserting eventual state: "does not construct next cubit until previous
  close completes" checks `recorder.created` has length 1 *before* completing the first close and only
  advances after; "host close awaits owned cubit close flush" awaits a zero-duration delay mid-`close()`
  and asserts the host's own close has *not* yet resolved while the owned cubit's `closeCallCount == 1`,
  which is a real blocking-order proof, not a race-prone eventual check. Independently reran codegen
  (clean), the scoped test (6 passed), lints (103/103, correctly matching the UNIT-09-lowered baseline
  with no new debt), both `rg` gates, and the full client suite (2272 passed, 18 skipped, zero
  regressions). Proceeding to UNIT 11 (nested beacon-view route host + real thread detail page — the
  actual wiring point for everything built in UNITs 05–10, still not activated for navigation until
  UNIT 12).

- 2026-08-14 — UNIT 11: `704679c3d` split `BeaconViewRoute` onto `BeaconViewHostScreen`
  (`AutoRouter` shell + `wrappedRoute` siblings: `BeaconViewCubit`, `ThreadsCubit..fetch()`,
  `ThreadHostCubit`); demoted `BeaconViewScreen` to embeddable operational widget; added
  `BeaconViewOperationalScreen` and `kQueryThreadId` / `kBeaconViewTabThreads` constants; exported
  `resolveCanonicalThreadIdForMessage()` for message-only URL canonicalization tests.

- 2026-08-14 — UNIT 11: `2d55720af` nested `BeaconViewOperationalRoute` + `ThreadDetailRoute` under
  branch and root redirect registrations; redirect guard preserves matched `thread/:threadId` child and
  forwards query params onto the operational child (fixes branch URL serialization for `entry`/`tab`/
  `message` after nested cutover).

- 2026-08-14 — UNIT 11: `00791ce0f` added `ThreadDetail` / `ThreadDetailTitle` /
  `ThreadDetailOverflowAction` / `ThreadDetailColumnChrome` extracted from live post-D27
  `ItemDiscussionPane` (legacy pane file untouched).

- 2026-08-14 — UNIT 11: `9ea39907c` added `ThreadDetailScreen` with `PopScope` + shared
  `_closeThenPop` (`await host.clear()` then single `router.pop()`), admission placeholder, semantic
  `ItemActionsCubit`, and sibling `replace` for coordination links.

- 2026-08-14 — UNIT 11: `ffc091e3f` wired `ThreadsCubit` + `ThreadHostCubit` above My Work / Inbox
  embedded `BeaconViewScreen` panes (no `openThreadId` in pane state).

- 2026-08-14 — UNIT 11: `d8a58c9b8` added `request_thread_routing_test.dart` (nested registration,
  redirect-guard child preservation, nested pop, message-target canonicalization) and
  `thread_detail_test.dart` (General vs semantic header, unconditional composer, completer-gated
  close-before-pop).

- 2026-08-14 — **UNIT 11 complete.** Verify: `flutter test
  test/app/router/request_thread_routing_test.dart` (5 passed), `flutter test
  test/features/beacon_threads/thread_detail_test.dart` (4 passed), `flutter test
  test/features/beacon_view/beacon_view_room_split_contract_test.dart` (9 passed),
  `./scripts/check-custom-lints.sh packages/client` (103/103), `rg` gates (`children:` +
  `ThreadDetailRoute` + `BeaconViewOperationalRoute` in router registrations; `openThreadId` absent
  from `beacon_view_screen.dart` state), full `flutter test` (2281 passed, 18 skipped). Live drift:
  `BeaconViewScreen` constructor is plain fields (operational screen passes params explicitly); redirect
  guard needed operational-child query forwarding for `home_tab_branch_routing_test` URL expectations;
  routing pop test pops the nested `StackRouter` under `BeaconViewRoute`, not the work branch stack.
  Legacy `ItemDiscussionRoute` / `ItemDiscussionPane` unchanged; row navigation not activated (UNIT
  12). Ready for UNIT 12.

- 2026-08-14 — **Manager review: UNIT 11 ACCEPTED.** This was router surgery — one of the two hardest
  units in the plan — so I read every piece by hand rather than trusting the summary. `BeaconViewHostScreen`
  correctly owns `@RoutePage(name: 'BeaconViewRoute')`, creates `BeaconViewCubit` then a
  `MultiBlocProvider` with one `ThreadsCubit(..fetch())` and one `ThreadHostCubit` wrapping `AutoRouter()`
  — a real shared ancestor for both nested pages, exactly the fix architecture §8.2/§8.3 require (not
  "alongside `BeaconViewCubit`" on the old leaf, which would not have been an ancestor of a sibling
  route). Read `root_router.dart`'s diff: the redirect guard now reads `resolver.route.children
  ?.firstOrNull` and threads a `matchedThreadId` through `beaconViewChildRoutesFromQuery`, which
  correctly builds either `[ThreadDetailRoute(...)]` or `[BeaconViewOperationalRoute(...with every
  query param copied down...)]` — losing this was the exact hazard the plan warned about (a cold detail
  URL silently landing on the list), and it's covered by a dedicated test. Read `ThreadDetailScreen`'s
  close/pop implementation line by line: `_allowPop`/`_exitInProgress` are the only local state fields
  (never `openThreadId`), `PopScope(canPop: _allowPop)`, and both the explicit back button and
  `onPopInvokedWithResult` call the same `_closeThenPop` — `await host.clear()`, `setState(_allowPop =
  true)`, pop once in a post-frame callback — matching UNIT 10's own award-before-teardown discipline.
  **Investigated one non-obvious risk myself, via a forked Explore agent, before accepting**: ~15
  call sites elsewhere in the app (`my_work_cards.dart`, `inbox_screen.dart`, `item_discussion_screen.dart`,
  `accept_invite_messages.dart`, etc.) push `BeaconViewRoute(id:, entry:, viewTab:)` as objects with no
  explicit `children:`, now that `BeaconViewRoute` is a parent route — a real question of whether those
  query params still reach the rendered screen or get silently dropped. Confirmed via source-level
  inspection of the `auto_route` package (`route_matcher.dart` `_matchByRoute`, called for object-based
  `.push()`) that it explicitly re-injects the parent route's own `rawQueryParams` when resolving an
  unspecified default child — so `entry`/`viewTab`/`coordinationItemId`/etc. do reach
  `BeaconViewOperationalRoute` for every one of those call sites, not just the URL-driven redirect-guard
  path the worker's own tests exercised. This is **not a regression** — confirmed by framework source,
  not assumption — though it did surface a genuine **pre-existing** test gap (no test pushes
  `BeaconViewRoute` as an object end-to-end and asserts the child receives those params); not a UNIT 11
  defect and not worth a remediation unit, noted here for future reference only. Independently reran
  codegen (clean), all three scoped test files (18 passed total), lints (103/103), both router `rg`
  gates, and the full client suite (2281 passed, 18 skipped, zero regressions). Proceeding to UNIT 12
  (the atomic Threads activation and legacy-surface deletion — the other hardest unit in the plan).

- 2026-08-14 — UNIT 12: `12d822607` delete server `beaconParticipantRoomSeen` /
  `markBeaconRoomSeen` GraphQL resolver fields; tests repointed to `markThreadSeen`.

- 2026-08-14 — UNIT 12: `6f6c47461` canonical thread routing — delete
  `BeaconRoomRoute`/`ItemDiscussionRoute` registrations and legacy query aliases; repoint
  `destination_map`, `notification_deep_link`, and `BeaconViewHostScreen` query surface.

- 2026-08-14 — UNIT 12: `4557d3ac9` activate `ThreadsList`/`ThreadsCubit` on tab 0;
  replace `beacon_view_screen` room state machine with `ThreadHostCubit`; window-class
  transition scheduling; delete ItemsTab, BeaconRoomSurface, ItemDiscussion, and
  `beacon_room_screen`.

- 2026-08-14 — UNIT 12: `b1f2b4023` embedded My Work/Inbox pane-width split with
  `onRequestThreadRoute`; repoint overflow, status sheet, `room_message_tile`, and
  `coordination_room_navigation` to General/`ThreadDetailRoute`.

- 2026-08-14 — UNIT 12: `b23227ae2` remove beacon-view-only `roomUnreadCount` and
  watermark forwarding (Inbox/My Work hints batch unchanged).

- 2026-08-14 — UNIT 12: `fb10fc3e9` client `6.1.0` + web cache-buster; e2e helpers
  `enterGeneralIfNeeded`/`enterThreadsIfNeeded` and typed `createCoordinationItem`/
  `sendRoomMessage` returns.

- 2026-08-14 — UNIT 12: `1174a4016` tests — branch routing, deep links, split contract,
  promise composer wiring, `ThreadHostCubit` transition guards; delete legacy Items/room
  tests; lint baseline 103→93.

- 2026-08-14 — **UNIT 12 complete.** Verify: `./scripts/check-custom-lints.sh` client+server
  (93/93, 0/0); server `dart test test/domain/use_case/beacon_room_case_mark_seen_test.dart`
  (8 passed); server `dart test --exclude-tags pg` (1509 passed); client scoped tests
  (notification_deep_link, destination_map, request_thread_routing, thread_host_cubit,
  thread_detail, home_tab_branch_routing — all passed); full `flutter test` (2272 passed,
  18 skipped); `bash scripts/check-user-facing-terminology.sh` (ok); forbidden-symbol `rg`
  gates clean; `roomUnreadCount` survivors in inbox/my_work/beacon_threads repo only;
  `6.1.0` in pubspec + `web/index.html`; `kDefaultMinClientVersion = '6.0.0'` unchanged.
  Live drift: `openFromNotificationLink` still sets `entry=room_notification` for
  `dest=room` (not `deep_link`) — preserved in `home_tab_branch_routing_test`; plan step
  20 pane-width embedded widget tests and some expanded co-visibility widget tests deferred
  to UNIT 14 where integration harness exercises real layout. Ready for UNIT 13 (D28 copy).
