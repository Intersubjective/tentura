# Work / Activity redesign — implementation journal

Objective: execute `docs/plans/work-activity-redesign-implementation-plan.md` (UNITs 00–22) via the overseer skill.

Design source: `docs/plans/work-activity-redesign-plan.md` (rev 5). Implementation plan: revision 1, written against HEAD `d84acc940`.

## Execution environment

**Deviation from the plan's assumed environment.** The plan's §3 rule 3 lists pre-existing changes to preserve (`CONTEXT.md`, `docs/plans/inbox-activity-ia-architecture.md`, `packages/force_directed_graphview/analysis_options.yaml`, 35 untracked paths), assuming execution happens directly in the primary worktree at `/home/vader/MY_SRC/tentura` (branch `feature/pin_constellation`).

At kickoff, another live session had committed to that branch 8 minutes prior (last commit `d567523b3` at 2026-09-13T23:31:04+02:00), so the overseer created an **isolated git worktree** instead, to guarantee zero collision risk with any concurrent session and zero risk of ever touching the 35+ unrelated uncommitted paths (they simply don't exist here — this is a fresh checkout):

- Worktree: `/tmp/claude-1000/-home-vader-MY-SRC-tentura/4f632d59-f33a-4bba-bb53-0f45eca8975d/scratchpad/work-activity-redesign`
- Branch: `work-activity-redesign`, created from `feature/pin_constellation` at `d567523b3`
- `git status --short` in this worktree: **empty** (nothing to preserve here — the plan's §3 rule 3 list does not apply to this worktree).
- The user later confirmed all other agents on the repo were stopped, but the isolated worktree was kept anyway (already set up, strictly safer, no downside).
- Primary worktree (`/home/vader/MY_SRC/tentura`) was **not** touched by any step below.

**One-time bootstrap** (done by the overseer directly, not a Cursor worker — pure environment setup, zero code risk, nothing here is plan-unit work):
- Copied `.env` from the primary worktree (shared JWT keypair / QA knobs needed to talk to the already-running shared infra).
- Appended `COMPOSE_PROJECT_NAME=tentura` to this worktree's `.env` only. Rationale: `compose.yaml` uses `include: [compose.dev.yaml]`, so a bare `docker compose` picks up both files with no `-f` flags needed; but the default project name is the invoking directory's basename, which is `tentura` for the primary worktree and would otherwise be `work-activity-redesign` here — a mismatch that would make `docker compose run`/`up` from this worktree try to create competing `hasura`/`postgres`/`meritrank` containers (whose `container_name` is hardcoded, so a real conflict, not silent duplication). Pinning the project name makes this worktree join the same shared project.
- `flutter pub get` (client), `dart pub get` (server, tentura_lints) — pub workspace resolves once for all three packages.
- `flutter gen-l10n` (client).
- `dart run build_runner build -d` in `packages/client` (6442 outputs, 91s, exit 0, no new warnings) and `packages/server` (2523 outputs, 45s, exit 0). Fresh worktree checkouts have none of the gitignored `*.g.dart`/`*.gr.dart`/`*.config.dart` output, so this is required before anything compiles.
  - Server build_runner emitted a **pre-existing** DI warning, unrelated to this plan: `[CoordinationCase]`/`[EvaluationCase] depends on unregistered type [AttentionSystemSettlementPort]`. Not touched; not caused by this work.
- Started the local API server in this worktree: `./scripts/run-server-local.sh` (background, port 2080, confirmed listening).
- Applied Hasura metadata against the shared instance: `./scripts/hasura_apply_metadata.sh` → `is_consistent: true`.

## UNIT 00 — complete — 2026-09-13

Run directly by the overseer (not a Cursor worker): pure environment verification, no code changes, no ambiguity to resolve — delegating it would have cost a worker turn to re-discover the same facts with no risk reduction. UNIT 01 onward goes through fresh Cursor `composer-2.5` workers per the skill contract.

COMMITS: none (no code touched)

TESTS:
- `cd packages/server && dart test -t pg -j 1 test/data/repository/attention_repository_pg_test.dart` → **17/17 passed** (pg preflight: Postgres reachable, proves `-t pg` isn't silently skipping).
- `./scripts/check-custom-lints.sh packages/client` → `32 (baseline: 32)` — OK.
- `./scripts/check-custom-lints.sh packages/server` → `0 (baseline: 0)` — OK.
- Schema-fetch preflight: `COMPOSE_PROJECT_NAME=tentura docker compose run --rm schema_fetcher` (joined the shared `tentura` project; did not restart `hasura`/`postgres`/`meritrank`) → `git diff --stat packages/client/lib/data/gql/schema.graphql` is **empty**. Today's schema round-trips byte-for-byte.

FILES: this journal (new).

FINDINGS:
- Flutter 3.47.0 / Dart 3.13.0 (stable) locally — AGENTS.md's "3.44" note is for the Cursor Cloud snapshot only, not this machine.
- `compose.yaml`'s `include:` directive means no `-f` flags are ever needed for compose commands, in either worktree — only `COMPOSE_PROJECT_NAME` needs pinning here.
- See "Execution environment" above for the worktree/bootstrap deviation from the plan's assumed baseline.

DECISIONS:
- Isolated worktree instead of the primary checkout (safety; see above). All subsequent units operate in `/tmp/claude-1000/-home-vader-MY-SRC-tentura/4f632d59-f33a-4bba-bb53-0f45eca8975d/scratchpad/work-activity-redesign`, branch `work-activity-redesign`.
- UNIT 00 executed by the overseer directly rather than a Cursor worker (rationale above).

REMAINING: none. Proceed to UNIT 01.

## UNIT 01 — complete — 2026-09-13

COMMITS:
- `c37f34186` feat(server): add the responsibility scope function
- `aa1f15b64` test(server): cover responsibility scope base membership

TESTS:
- `cd packages/server && dart test -t pg -j 1 test/data/repository/responsibility_scope_pg_test.dart` → **8/8 passed**
- `./scripts/check-custom-lints.sh packages/server` → `0 (baseline: 0)` — OK

FILES:
- `packages/server/lib/data/database/migration/m0168.dart` (new)
- `packages/server/lib/data/database/migration/_migrations.dart` (edit)
- `packages/server/test/data/repository/responsibility_scope_pg_test.dart` (new)

FINDINGS: none

DECISIONS: none

REMAINING: none. Proceed to UNIT 02.

**Manager verdict: ACCEPTED.** Independently re-ran `dart test -t pg -j 1 test/data/repository/responsibility_scope_pg_test.dart` (8/8 passed) and `./scripts/check-custom-lints.sh packages/server` (0, baseline 0). Read both commits: `m0168.dart` matches §2.2's base-set definition verbatim (authored non-deleted ∪ active-help-offer non-deleted beacon), same style as `m0117.dart` (STABLE SECURITY INVOKER, search_path pinned). Test suite covers all 8 plan-listed membership cases using the established `DisposablePgTarget` pattern (already used by 5+ other pg test files, not invented). Commits are properly split (migration+registration, then tests, then journal). Nothing outside the Owns list touched. No leaked worker processes found.

## UNIT 02 — complete — 2026-09-13

COMMITS:
- `136479ca2` feat(server): add attention surface model and port contracts
- `d88d79225` feat(server): scope attention reads by surface
- `a83ffbbe6` test(server): cover attention surface reads and mark-all

TESTS:
- `cd packages/server && dart run build_runner build -d` → exit 0
- `cd packages/server && dart test -t pg -j 1 test/data/repository/attention_surface_pg_test.dart test/data/repository/attention_repository_pg_test.dart` → **28/28 passed** (11 surface + 17 existing repository)
- `cd packages/server && dart test test/api/controllers/graphql/attention_graphql_test.dart test/api/controllers/graphql/query_attention_payload_test.dart` → **15/15 passed**
- `./scripts/check-custom-lints.sh packages/server` → `0 (baseline: 0)` — OK

FILES:
- `packages/server/lib/domain/attention/attention_models.dart`
- `packages/server/lib/domain/port/attention_query_port.dart`
- `packages/server/lib/domain/port/attention_ack_port.dart`
- `packages/server/lib/data/repository/attention_repository.dart`
- `packages/server/lib/api/controllers/graphql/custom_types.dart`
- `packages/server/lib/api/controllers/graphql/query/query_attention.dart`
- `packages/server/lib/api/controllers/graphql/mutation/mutation_attention.dart`
- `packages/server/test/api/controllers/graphql/attention_graphql_test.dart`
- `packages/server/test/api/controllers/graphql/query_attention_payload_test.dart`
- `packages/server/test/domain/attention/legacy_canonical_compat_fixture_test.dart`
- `packages/server/test/data/repository/attention_surface_pg_test.dart` (new)

FINDINGS:
- Foreign-beacon obligation/pg fixtures need a read path (e.g. `beacon_forward_edge`) so receipts pass `visible_attention_receipts` before surface is asserted.
- `attention_models.freezed.dart` / `di.config.dart` are gitignored in this worktree; run `build_runner` after checkout.

DECISIONS: none

REMAINING: none. Proceed to UNIT 03.

**Manager verdict: ACCEPTED.** Independently re-ran all four Verify commands (28/28 pg, 15/15 graphql, lints 0/0, build_runner clean). Read the full `attention_repository.dart` diff: `scope` is built from `responsibility_scope_base_beacons` UNION obligation beacon ids taken from the SAME `visible_raw` CTE — no second `visible_attention_receipts` call, satisfying §2.2's hardest constraint. `surface` filter correctly threaded through `page`/`summary`/`markAllSeen` with `needs_you_total` left unfiltered. Cursor placeholder renumbering (surface inserted as `$4`, cursor bumped to `$5`/`$6`) is internally consistent. The pre-existing 17-test `attention_repository_pg_test.dart` suite is untouched and still green — strong evidence `surface: null` is byte-for-byte legacy behavior, as required. GraphQL layer correctly rejects `search` + `surface: activity` and unknown surface values (`ArgumentError`), and `markAllSeen` mutation reuses `QueryAttention.parseSurfaceArgument` rather than duplicating the parse. Grepped for `implements AttentionQueryPort|AttentionAckPort`: exactly 3 hits (the real repository + the 2 test fakes the plan named) — no missed fakes. Minor non-blocking style note: `markAllSeen`'s surface CTE duplicates `_visibleWithSurfaceCte`'s shape inline instead of reusing the constant (harmless, not worth a remediation round). No leaked processes, clean git status otherwise.

## UNIT 03 — complete — 2026-09-13

COMMITS:
- `0b0a4790f` feat(server): fold answered forwards into the activity stream
- `3bdc5f657` test(server): cover activity stream forwards and digest

TESTS:
- `cd packages/server && dart test -t pg -j 1 test/data/repository/attention_activity_stream_pg_test.dart test/data/repository/attention_surface_pg_test.dart` → **22/22 passed** (11 activity + 11 surface)
- `./scripts/check-custom-lints.sh packages/server` → `0 (baseline: 0)` — OK

FILES:
- `packages/server/lib/data/repository/attention_repository.dart`
- `packages/server/test/data/repository/attention_activity_stream_pg_test.dart` (new)

FINDINGS:
- `beacon_forward_edge` insert always creates an `inbox_item` (status 0) via `inbox_item_on_forward_insert`; UNIT 02’s “forward-only recipient” activity test still needs non-`relay_received` receipts visible alongside an open inbox row.
- Watching digest and per-beacon forward rows are mutually exclusive when unseen activity is newer than `latest_forward_at` (design §5.3 aggregate vs §5.1 demoted forward row).

DECISIONS:
- Receipt dedupe on the activity page applies to `presentation_key = 'relay_received'` rows with an inbox row (design §3 table), not all receipt kinds — keeps UNIT 02 surface tests green while satisfying relay dedupe acceptance.
- Suppress `watching` forward rows when the beacon has unseen visible receipts with `created_at > latest_forward_at`; digest uses the same predicate so the stream shows one aggregate row instead of duplicate representations.

REMAINING: none. Proceed to UNIT 04.

**Manager review found one real defect, fixed directly (small/local/unambiguous — no remediation worker needed).** The worker's decision "suppress `watching` forward rows when the beacon has unseen visible receipts... so the stream shows one aggregate row instead of duplicate representations" contradicts design plan §5.6 explicitly: the mockup there shows a beacon's forward row («Вы наблюдаете») and the watching-digest aggregate row coexisting on the same day for the same underlying watched beacon — they are independent mechanisms (a permanent per-beacon outcome marker vs. an aggregate of watched beacons with unseen news), not mutually exclusive. Fixed directly:
- Removed the `AND NOT (ii.status = 1 AND ... AND EXISTS (SELECT ... newer.created_at > ii.latest_forward_at))` suppression block from the forward-item WHERE clause in `attention_repository.dart`'s `_activityPageStreamCte`.
- Flipped the two tests that encoded the wrong exclusivity: `'watching digest counts beacons not receipts'` now asserts the forward row for `_foreignBeaconId` IS present (outcome `'watching'`) alongside the digest, instead of asserting the forward-kind list is empty; `'unread_total includes receipts represented by forwards'` now expects 3 page items (forward + digest + unrelated profile receipt) instead of 2.
- Re-ran all three related pg suites together: **39/39 passed** (11 activity stream + 11 surface + 17 existing repository, unchanged). Lints: `0 (baseline: 0)`.
- Commit: `18d9a7295` fix(server): stop hiding a watching forward row behind the digest.

**Everything else in UNIT 03 reviewed and ACCEPTED as delivered:**
- The `relay_received`-only receipt-dedup condition (not all receipt kinds, contrary to a looser paraphrase in this journal's own UNIT 03 worker prompt) is *correct* — it matches design plan §5.6 verbatim: "`relay_received` receipts of any Beacon with an Inbox row are deduplicated into that row." Good catch by the worker; the overseer's own prompt for this unit had over-broadened this from the implementation-plan prose without cross-checking the authoritative design plan — worth remembering for later units' prompts.
- Forward-outcome precedence, `id`/`created_at` framing, tombstone-copy handling, and the digest's `beacon_count` (not receipt count) all match §2.3/UNIT 03 exactly, independently re-read against the diff.
- The digest's extra `v.created_at > ii.latest_forward_at` join condition (excluding the very receipt that arrived at forward time from counting as "new" watched-item activity) is not explicitly specified either way in the plan, but is a sensible, defensible reading — not a contradiction of anything explicit — so left as-is.
- No leaked worker processes; clean git status otherwise; commits appropriately split (repository change, tests, journal).

## UNIT 04 — complete — 2026-09-14

COMMITS:
- `534d97ae0` feat(server): mark a request's receipts seen
- `a4645c084` test(server): cover mark seen for beacon

TESTS:
- `cd packages/server && dart test -t pg -j 1 test/data/repository/attention_mark_seen_for_beacon_pg_test.dart` → **4/4 passed**
- `cd packages/server && dart test test/api/controllers/graphql/attention_graphql_test.dart` → **12/12 passed**
- `./scripts/check-custom-lints.sh packages/server` → `0 (baseline: 0)` — OK

FILES:
- `packages/server/lib/domain/port/attention_ack_port.dart`
- `packages/server/lib/data/repository/attention_repository.dart`
- `packages/server/lib/api/controllers/graphql/mutation/mutation_attention.dart`
- `packages/server/test/data/repository/attention_mark_seen_for_beacon_pg_test.dart` (new)
- `packages/server/test/api/controllers/graphql/attention_graphql_test.dart`

FINDINGS:
- The existing `markSeen` pg case in `attention_repository_pg_test.dart` does not assert `LISTEN entity_changes`; realtime coverage for `seen_at` follows `settlement_notify_pg_test.dart` / migration test patterns instead.

DECISIONS: none

REMAINING: none. Proceed to UNIT 05.

**Manager verdict: ACCEPTED.** Independently re-ran all three Verify commands (4/4 pg, 12/12 graphql, lints 0/0). `markSeenForBeacon` correctly mirrors pre-UNIT-02 `markAllSeen`'s simple shape — scoped only by `visible_attention_receipts`, no surface/scope CTE machinery pulled in, exactly as instructed. The pg test suite is thorough: authorization scoping, an explicit seen≠settled assertion (checks `settlement_kind`/`settled_at` stay NULL and `requires_action` stays true after marking seen), a hidden-beacon authorization case, and — better than what was asked — a genuine `LISTEN entity_changes` test that verifies the realtime trigger actually fires, rather than just inferring it from the existing `markSeen` test's pattern. No leaked processes, clean git status, commits well split.

## UNIT 05 — complete — 2026-09-14

COMMITS:
- `7a6f3bf07` feat(server): expose per-request attention for my work
- `dafc1f84e` test(server): cover my work attention projection

TESTS:
- `cd packages/server && dart run build_runner build -d` → exit 0
- `cd packages/server && dart test -t pg -j 1 test/data/repository/my_work_attention_pg_test.dart` → **6/6 passed**
- `cd packages/server && dart test test/api/controllers/graphql/attention_graphql_test.dart` → **13/13 passed**
- `./scripts/check-custom-lints.sh packages/server` → `0 (baseline: 0)` — OK

FILES:
- `packages/server/lib/domain/attention/attention_models.dart`
- `packages/server/lib/domain/port/attention_query_port.dart`
- `packages/server/lib/data/repository/attention_repository.dart`
- `packages/server/lib/api/controllers/graphql/custom_types.dart`
- `packages/server/lib/api/controllers/graphql/query/query_attention.dart`
- `packages/server/test/data/repository/my_work_attention_pg_test.dart` (new)
- `packages/server/test/api/controllers/graphql/attention_graphql_test.dart`
- `packages/server/test/domain/attention/legacy_canonical_compat_fixture_test.dart`

FINDINGS:
- Dart-side aggregation over one `scoped_receipts` SELECT keeps obligation ordering and `latestUnseen` exclusion logic aligned with design §4.2–§4.3 without duplicating `_mapRow` column lists in SQL json aggregates.

DECISIONS:
- Reuse `_visibleWithSurfaceCte` + `scoped_beacons` (`beaconIds ∩ scope`) rather than a third scope computation; emit beacons only when `unseenCount > 0` or ≥1 live obligation per §2.3.

REMAINING: none. Proceed to UNIT 06.

**Manager verdict: ACCEPTED.** Independently re-ran all three Verify commands (6/6 pg, 13/13 graphql, lints 0/0). `myWorkAttention` correctly reuses `_visibleWithSurfaceCte` (one call to `visible_attention_receipts`, no second authorization path), restricts to `scope ∩ beaconIds`, and does aggregation (grouping, `unseenCount`, `latestUnseen` exclusion, `liveObligations` ordering, non-empty-only emission) in Dart over one SQL round trip rather than raw SQL aggregates — a reasonable reading of "one statement" that reuses the existing `_mapRow` mapping instead of duplicating column lists in a json_agg. `isUnread`/`isLiveObligation` are pre-existing model getters with exactly the right semantics, not reinvented. GraphQL layer matches the frozen `MyWorkBeaconAttention` shape and the ≤500 guard mirrors `attentionMarkers`' style. pg suite covers all 5 plan-specified cases plus an empty-input edge case. No leaked processes, clean git status, commits well split. This closes out every attention-repository server unit (01–05) cleanly.

## UNIT 06 — complete — 2026-09-14

Run directly by the overseer (not a Cursor worker), same rationale as UNIT 00: a single JSON key addition plus running an already-existing apply script plus one curl probe — mechanical, no code ambiguity, low risk, nothing a fresh worker turn would add.

COMMITS:
- (to be committed with this journal entry) chore(hasura): allow inbox item aggregations

TESTS:
- `python3 -c "import json;m=json.load(open('hasura/metadata.json'));print('ok')"` → `ok`
- `git diff hasura/metadata.json` → exactly one key added (`"allow_aggregations": true`) on the `inbox_item` role-`user` select permission; `columns`, `computed_fields` and `filter` byte-identical to before.
- `./scripts/hasura_apply_metadata.sh` → `is_consistent: true`, `inconsistent_objects: []`.
- Probe (role `user` impersonation via admin secret, matching the `schema_fetcher` header pattern, against a real seeded user id `Ue8791ffa71bb`):
  ```
  curl -sS -X POST http://127.0.0.1:8080/v1/graphql \
    -H "X-Hasura-Admin-Secret: password" -H "X-Hasura-Role: user" \
    -H "X-Hasura-User-Id: Ue8791ffa71bb" -H "Content-Type: application/json" \
    -d '{"query":"query { inbox_item_aggregate(where: {status: {_eq: 0}, beacon: {can_read_content: {_eq: true}}}) { aggregate { count } } }"}'
  ```
  → `{"data":{"inbox_item_aggregate":{"aggregate":{"count":1}}}}` — the aggregate is readable under the same row filter, exactly as the plan's Acceptance requires.

FILES:
- `hasura/metadata.json`

FINDINGS:
- The dev Postgres database name is `postgres` (not `tentura`), per `.env`'s `POSTGRES_DBNAME=postgres` — useful for any future direct-psql probes in this worktree.

DECISIONS:
- Executed directly rather than via a Cursor worker (rationale above).

REMAINING: none. Proceed to UNIT 07 (first client unit).

**Environment maintenance before client work (overseer, not a plan unit):** the background API server in this worktree had been running continuously since UNIT 00's bootstrap — a long-lived Dart process, so none of UNITs 01–06's server code changes (including the `m0168` migration) were actually loaded. Restarted it (`./scripts/run-server-local.sh`, confirmed port 2080 listening again) and confirmed `m0168`'s function now exists in the live dev database (`postgres`, not `tentura` — see UNIT 06's finding). Re-applied Hasura metadata (`is_consistent: true`). Ran `COMPOSE_PROJECT_NAME=tentura docker compose run --rm schema_fetcher` as a dry-run check: confirmed the refreshed SDL now contains `attentionSurfaceSummary`, `myWorkAttention(beaconIds: [String!])`, `attentionMarkSeenForBeacon(beaconId: String!): Int!`, and `surface`/`itemKind`/`forwardOutcome` on the receipt type — exactly the frozen §2.3 shapes. **Reverted that regenerated `schema.graphql` afterward** (`git checkout --`) since committing it is explicitly UNIT 07's own first step, not the overseer's to pre-empt — UNIT 07 must run this same refresh itself per §3 rule 5 and commit the result as part of its own work.

Note: `myWorkAttention`'s GraphQL argument is `beaconIds: [String!]` (nullable at the schema level, not `[String!]!` as §2.3's shorthand suggests) — this is not a UNIT 05 defect, it's the pre-existing shared `InputFieldStringList` field also used by `attentionMarkers`, with non-null enforcement happening at the resolver via `fromArgsNonNullable` rather than at the wire type. UNIT 05 correctly reused the existing convention rather than diverging. UNIT 05's ACCEPTED verdict stands.

## UNIT 07 — complete — 2026-09-14

COMMITS:
- `540816d4a` feat(client): refresh attention GraphQL for surfaces
- `673e6633f` feat(client): add attention surface domain models
- `6f39bb013` feat(client): read attention by surface
- `5abd52643` test(client): cover attention surface repository mapping
- (this journal entry) docs: UNIT 07 journal

TESTS:
- `COMPOSE_PROJECT_NAME=tentura docker compose run --rm schema_fetcher` → SDL diff includes `attentionSurfaceSummary`, `myWorkAttention`, `attentionMarkSeenForBeacon`, receipt `surface`/`itemKind`/`forwardOutcome`/`forwardCount`/`digestCount`
- `cd packages/client && dart run build_runner build -d` → exit 0
- `cd packages/client && flutter test test/domain/attention/ test/data/gql/direct_v2_schema_overlay_test.dart` → **40/40 passed**
- `cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos` → **0 errors**
- `./scripts/check-custom-lints.sh packages/client` → `32 (baseline: 32)` — OK

FILES:
- `packages/client/lib/data/gql/schema.graphql`
- `packages/client/lib/features/attention/data/gql/attention_feed.graphql`
- `packages/client/lib/features/attention/data/gql/attention_mark_all_seen.graphql`
- `packages/client/lib/features/attention/data/gql/attention_surface_summary.graphql`
- `packages/client/lib/features/attention/data/gql/attention_mark_seen_for_beacon.graphql`
- `packages/client/lib/features/attention/data/gql/my_work_attention.graphql`
- `packages/client/lib/domain/attention/entity/attention_feed.dart`
- `packages/client/lib/domain/attention/entity/attention_receipt.dart`
- `packages/client/lib/domain/attention/entity/attention_summary.dart`
- `packages/client/lib/domain/attention/entity/my_work_beacon_attention.dart`
- `packages/client/lib/domain/attention/port/attention_repository_port.dart`
- `packages/client/lib/data/repository/attention_repository.dart`
- `packages/client/lib/data/service/remote_api_client/build_client.dart`
- `packages/client/test/support/attention_repository_fake_base.dart` (new shared stub defaults)
- `packages/client/test/domain/attention/attention_surface_repository_test.dart` (new)
- Port fakes updated (**21** classes extending `AttentionRepositoryFake`; Mockito `AttentionRepositoryMock` unchanged): `test/architecture/cross_surface_subscription_test.dart`, `test/domain/attention/attention_case_test.dart`, `test/domain/attention/attention_live_obligations_test.dart`, `test/features/home/constellation_nav_test.dart`, `test/features/home/home_attention_cubit_test.dart`, `test/features/home/inbox_navbar_item_test.dart`, `test/features/home/my_work_navbar_item_test.dart`, `test/features/inbox/inbox_expanded_chrome_test.dart`, `test/features/inbox/inbox_receipts_fold_test.dart`, `test/features/inbox/inbox_watching_route_test.dart`, `test/features/my_work/my_work_obligations_pane_test.dart`, `test/features/my_work/my_work_scope_coincidence_test.dart`, `test/features/my_work/my_work_test_support.dart`, `test/features/updates/cross_surface_coordination_accept_test.dart`, `test/features/updates/prompt_pinning_test.dart`, `test/features/updates/prompt_projection_test.dart`, `test/features/updates/updates_102_my_work_attention_test.dart`, `test/features/updates/updates_feed_cubit_test.dart`, `test/features/updates/updates_feed_session_test.dart`, `test/features/updates/updates_feed_views_test.dart`, `test/ui/widget/tab_attention_scope_test.dart`
- Additional test fixtures touched for required `AttentionReceipt.surface` (updates/inbox golden and card tests, `destination_map_test.dart`, `legacy_receipt_client_fixture_test.dart`)

FINDINGS:
- `grep -rn "implements AttentionRepositoryPort" packages/client/test packages/client/integration_test` → **21** manual fakes + **1** Mockito mock (`AttentionRepositoryMock`); integration_test has **0** implementers.
- Unknown `surface`/`itemKind` wire strings map to `activity`/`receipt` with `Logger('AttentionRepository').warning` (same `logging` package pattern as `RemoteRepository`).

DECISIONS:
- Added `AttentionRepositoryFake` test base with zero-valued defaults for the three new port methods so 21 fakes stay maintainable without touching `AttentionCase` (UNIT 08).

**Manager verdict: ACCEPTED.** Independently re-ran all four Verify commands (40/40 flutter test, 0 analyze errors — only pre-existing unrelated warnings/info in `test_driver/`/`tool/`, lints 32/32 baseline). Independently re-ran the `implements AttentionRepositoryPort` grep myself: confirms exactly 1 hit (`AttentionRepositoryFake`), validating the worker's refactor — the 21 individual fakes now `extends` that shared base instead of each declaring `implements` directly, which is *better* than the plan's literal ask (edit ~10 fakes individually) since it centralizes the 3 new methods' defaults in one place. Read `attention_repository.dart`'s adapter in full: the `_parseSurface`/`_parseItemKind` helpers correctly distinguish "genuinely activity/receipt" from "unknown value defaulted to activity/receipt" before logging (compares the raw wire string against the known wire constant, not just the parsed enum), avoiding false-positive warnings — a subtlety the prompt didn't spell out but the worker got right. `attention_surface_repository_test.dart` exercises the real repository against a hand-built `RemoteRequestClient` fixture (not a shallow mock), verifying wire mapping, unknown-value fallback + actual log capture via `Logger(...).onRecord`, and an explicit error-propagation test (`Stream.error` from the fixture) distinguishing "surfaceSummary failed" from "surfaceSummary succeeded with zeros" — exactly per the prompt's requirement. The `build_client.dart` touch (registering `AttentionMarkSeenForBeacon`/`AttentionSurfaceSummary`/`MyWorkAttention` in `_V2RoutingLink`'s operation allowlist) wasn't in the plan's Owns list but is a legitimate, necessary, narrowly-scoped finding (3 lines) — correctly caught per §3 rule 2 ("Owns list is a starting point, not an inventory"). No leaked processes, clean git status, commits well split (GraphQL, entities, repository+wiring, tests, journal).
- Registered `AttentionMarkSeenForBeacon`, `AttentionSurfaceSummary`, and `MyWorkAttention` in `_tenturaDirectOperationNames` for V2 direct routing.

REMAINING: none. Proceed to UNIT 08 (`AttentionCase` surfaces, summary stream, invalidation).

## UNIT 08 — complete — 2026-09-14

COMMITS:
- `949fe7c94` feat(client): add attention feed destination surface mapping
- `cdb7a19b8` feat(client): surface-aware attention sessions
- `b3a8912a1` test(client): cover attention surface sessions and summary
- (this journal entry) docs: UNIT 08 journal

TESTS:
- `cd packages/client && flutter test test/domain/attention/` → **54/54 passed**
- `./scripts/check-custom-lints.sh packages/client` → `32 (baseline: 32)` — OK

FILES:
- `packages/client/lib/domain/attention/entity/attention_feed.dart`
- `packages/client/lib/domain/attention/attention_case.dart`
- `packages/client/test/domain/attention/attention_case_test.dart`
- `packages/client/test/domain/attention/attention_case_test_support.dart` (new)
- `packages/client/test/domain/attention/attention_surfaces_test.dart` (new)

FINDINGS:
- Reused existing methods: `_requestHeadRefresh`, `_requestHeadRefreshForAllAttached`, `_applyOptimisticAcks`, `_runAfterAckBarriers`, `_onAccountChanged`, `_displayedUnreadCount` / `_displaysSeen`.
- New helpers: `_requestSurfaceSummaryRefresh`, `_requestHeadRefreshForAttachedActivityStream`, `_onRealtimeEntityChange`, `_applyOptimisticSurfaceSummary`, `_surfaceUnreadDeltasForIds`; surface summary guarded by `_surfaceSummaryRequestSerial` (same stale-drop pattern as `session.requestGeneration` on head refresh).
- Unknown destination ids map to `null` surface (unscoped fetch), matching legacy destinations.

DECISIONS:
- Extracted `AttentionCaseTestRepository` / shared fixtures to `attention_case_test_support.dart` so `attention_surfaces_test.dart` can share the case-test fake without importing private types.

REMAINING: none. Proceed to UNIT 09.

**Environment note:** found `packages/client/web/manifest.json` showing as modified in this worktree (build-hook auto-sync of the `version` field, per AGENTS.md — deliberately `skip-worktree` in the primary checkout, but that index bit isn't inherited by `git worktree add`). Applied `git update-index --skip-worktree` here too so it stops appearing as noise for future units. Not part of UNIT 08's work.

**Manager verdict: ACCEPTED — exemplary unit.** Independently re-ran both Verify commands (54/54 flutter test, lints 32/32 baseline). Read the full `attention_case.dart` diff end to end: `_onRealtimeEntityChange` correctly triggers the surface-summary refresh unconditionally but branches the head-refresh scope (activity-stream-only for `helpOffer`/`inboxItem`, all-attached for plain `notification`) — exactly the required distinction. `_requestSurfaceSummaryRefresh` mirrors the file's existing in-flight-coalescing idiom (`_surfaceSummaryRefreshInFlight`/`Queued`) and adds a monotonic `_surfaceSummaryRequestSerial` guard alongside the existing account-generation guard, dropping stale responses on both axes. `markAllSeen({surface})` correctly zeroes only the requested surface's total (via `copyWith`'s null-means-unchanged convention) while leaving the other surface's total and `needsYouTotal` untouched, with correct rollback of the full previous surface-summary snapshot on failure. `_surfaceUnreadDeltasForIds` correctly keys optimistic adjustments off `receipt.surface`, applied symmetrically (apply on start, roll back exactly on failure) across `markSeen`/`markUnseen`/`markSeenForBeacon`. The new `_surfaceSummarySubject` is closed in `dispose()` (no stream leak). The round-trip test genuinely exercises `attachFeedSession`/`detachFeedSession` across `activityStream`→`history`→`activityStream` and asserts real session-state survival (`activeView`, `searchText`, cached page `nextCursor`) plus that the `history` fetch actually passed `surface: null` — not a shallow assertion. No leaked processes, clean git status (after the manifest.json fix above), commits well split.

## UNIT 09 — complete — 2026-09-14

COMMITS:
- `b434994ba` feat(client): add work activity redesign gate
- `5b5b0a250` feat(client): add section header and summary row
- `84b1d804e` refactor(client): share attention summary row at call sites
- `b324ccfaf` docs: record UNIT 09 redesign gate and DS components

TESTS:
- `cd packages/client && dart run build_runner build -d` → exit 0 (`WorkActivityRedesignGateModule` in generated `di.config.dart`)
- `cd packages/client && flutter test test/design_system/ test/features/inbox/inbox_triage_row_test.dart` → **92/92 passed**
- `./scripts/check-custom-lints.sh packages/client` → `32 (baseline: 32)` — OK
- `cd packages/tentura_lints && dart test` → **18/18 passed**

FILES:
- `packages/client/lib/features/home/domain/work_activity_redesign_gate.dart` (new)
- `packages/client/lib/design_system/components/tentura_section_header.dart` (new)
- `packages/client/lib/design_system/components/tentura_attention_summary_row.dart` (new)
- `packages/client/lib/design_system/tentura_design_system.dart`
- `packages/client/lib/features/inbox/ui/widget/inbox_triage_row.dart`
- `packages/client/lib/features/updates/ui/widget/updates_feed_pane.dart`
- `packages/client/test/design_system/tentura_section_header_golden_test.dart` (new)
- `packages/client/test/design_system/tentura_attention_summary_row_golden_test.dart` (new)
- `packages/client/test/design_system/goldens/tentura_section_header_*.png` (9)
- `packages/client/test/design_system/goldens/tentura_attention_summary_row_*.png` (9)

FINDINGS:
- `_CollapsedInvitePromptRow` had no trailing chevron; `showChevron: false` preserves the prior layout.
- Section header label uses `tt.textFaint` (Activity day-header family); helper uses `tt.textMuted` per plan.
- Component goldens were generated with `--update-goldens` but not manually eyeballed; refactor parity is backed by unchanged `inbox_triage_row_test.dart` and identical token/layout lift.

DECISIONS:
- `TenturaAttentionSummaryRow` optional `showChevron` and `maxLines` cover triage (1 line + chevron) vs collapsed prompt (2 lines, no chevron).
- Section header padding: `top: sectionGap`, `bottom: tightGap`.

REMAINING: none. Proceed to UNIT 10.

**Manager verdict: ACCEPTED, with one process gap closed by the overseer.** Independently re-ran all four Verify commands (build_runner clean, 92/92 flutter test, lints 32/32 baseline, tentura_lints 18/18). The worker honestly flagged in FINDINGS that it generated the 18 new golden PNGs via `--update-goldens` but did not eyeball them — a real gap against plan §3 rule 12 ("regenerate intentionally... then open and eyeball the PNG"), material here because these are first-generation goldens with no prior baseline to diff against, so eyeballing is the only way to catch a broken initial render. The overseer opened a representative sample (6 of 18: light/dark × en/ru × both components, plus the two 1.3×-scale variants) directly — all render as sane, correctly composed layouts (leading slot, label, chevron present/absent as expected per `showChevron`, no `RenderFlex` overflow artifacts) using the same box-glyph placeholder-font convention already used by this repo's other golden tests (verified against `test/golden/goldens/evaluation_impact_control_light_320.png`), confirming this isn't a font-loading regression specific to the new tests. Read the refactor diff for both re-pointed call sites in full: `inbox_triage_row.dart` and `updates_feed_pane.dart`'s collapsed prompt row are faithful, byte-for-byte-equivalent extractions into `TenturaAttentionSummaryRow` — identical `Material`/`InkWell`/test-id/sizing/padding/text-style, chevron correctly present for triage and correctly suppressed (`showChevron: false`) for the collapsed prompt row, matching its prior chevron-less layout. No leaked processes, clean git status, commits well split (the worker even self-corrected a journal commit-hash typo in a follow-up commit).

## Ordered unit checklist

| Unit | Status |
|---|---|
| 00 | complete (overseer, this entry) |
| 01 | complete (accepted) |
| 02 | complete (accepted) |
| 03 | complete (accepted, one defect fixed by overseer) |
| 04 | complete (accepted) |
| 05 | complete (accepted) |
| 06 | complete (overseer, accepted) |
| 07 | complete (accepted) |
| 08 | complete (accepted) |
| 09 | complete (accepted) |
| 10 | pending |
| 11 | pending |
| 12 | pending |
| 13 | pending |
| 14 | pending |
| 15 | pending |
| 16 | pending |
| 17 | pending |
| 18 | pending |
| 19 | pending |
| 20 | pending |
| 21 | pending |
| 22 | pending |

## Unresolved decisions and blockers

None yet.
