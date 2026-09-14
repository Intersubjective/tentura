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

## UNIT 10 — complete — 2026-09-14

COMMITS:
- `609b103e4` fix(client): clarify notification rows

TESTS:
- `cd packages/client && flutter test test/features/updates/` → **87/87 passed**
- `./scripts/check-custom-lints.sh packages/client` → `32 (baseline: 32)` — OK
- `cd packages/client && flutter test --update-goldens test/features/updates/updates_feed_tile_golden_test.dart test/features/updates/invite_accepted_setup_golden_test.dart` → **6/6 passed** (goldens regenerated before final test run)

FILES:
- `packages/client/lib/features/updates/ui/widget/updates_feed_tile.dart`
- `packages/client/lib/features/updates/ui/widget/updates_day_groups.dart`
- `packages/client/lib/features/updates/ui/widget/updates_feed_pane.dart`
- `packages/client/lib/features/updates/updates_receipt_display_copy.dart`
- `packages/client/pubspec.yaml` (7.6.7 → 7.6.8)
- `packages/client/web/index.html` (`flutter_bootstrap.js?v=7.6.8`)
- `packages/client/test/features/updates/updates_day_groups_test.dart`
- `packages/client/test/features/updates/updates_receipt_display_copy_test.dart`
- `packages/client/test/features/updates/updates_receipt_card_test.dart`
- `packages/client/test/features/updates/trust_change_receipt_card_test.dart`
- `packages/client/test/features/updates/goldens/updates_dense_row_dark_compact.png`
- `packages/client/test/features/updates/goldens/invite_accepted_compact_card_light.png`
- `packages/client/test/features/updates/goldens/invite_accepted_compact_card_dark.png`

FINDINGS:
- `updatesFeedGlyphFor` already mapped trust directions, `mutual_connection_formed`, `offer_accepted` (in send group), and `relay_received` (`TenturaIcons.send` forward glyph); added explicit `request_status_changed` (`TenturaIcons.switcher`) and split `offer_accepted` to `TenturaIcons.favorites`.
- Day headers reuse `formatScheduleDate` from `schedule_date_format.dart` (same `MMMd` / `yMMMd` year rule as beacon schedule copy).
- Eyeballed regenerated row goldens: `updates_dense_row_dark_compact.png` shows event headline (“Asked of you”), subject line (“Garden cleanup”), send glyph with unread dot, trailing `more_vert` (no hollow seen toggle), and “Mark done” action; `invite_accepted_compact_card_dark.png` shows profile glyph, unread dot, overflow menu, and unchanged invite-specific headline/body overrides (person name + setup CTA).

DECISIONS:
- Mark seen/unseen: overflow `PopupMenuButton`, desktop secondary-tap toggles, touch long-press opens the same menu (alongside overflow/hover — not long-press alone), hover toolbar with visibility + more (mirrors `room_message_tile.dart` pattern).
- `resolveUpdatesFeedRowCopy`: headline = server event title (or override); supporting line = `beaconTitle` from payload when present.

REMAINING: none. Proceed to UNIT 11.

**Manager verdict: ACCEPTED.** Independently re-ran both Verify commands (87/87 flutter test, lints 32/32 baseline). Read the full `updates_feed_tile.dart` gesture-handling diff against `room_message_tile.dart`: near-exact structural match — same `_touchOrStylus` device-restricted `LongPressGestureRecognizer`, same `onSecondaryTap` pattern, same `MouseRegion`-based hover toolbar with the identical rationale comment about hover only firing for pointer devices. Long-press opens the same overflow menu reachable via the always-visible overflow button and the hover toolbar — never the sole affordance, satisfying "never long-press alone." Confirmed `formatScheduleDate` (reused from `schedule_date_format.dart`, not reinvented) implements exactly the `DateFormat.MMMd` / `DateFormat.yMMMd`-when-year-differs rule. Read the `resolveUpdatesFeedRowCopy` diff: headline is now unconditionally the event title (previously it could be overridden by `beaconTitle`, which was the bug this unit fixes); the supporting line now prioritizes `bodyOverride` → `beaconTitle` (subject) → excerpt — the correct swapped priority. The unrequested `pubspec.yaml`/`web/index.html` version bump (7.6.7→7.6.8) is correct per AGENTS.md's unconditional invariant ("user-visible client changes require a semver bump... web cache-buster must ship with every version bump") since this is the one real user-visible pre-flip change — verified both files carry the same `7.6.8`. Personally opened all three regenerated golden PNGs: clean compositions, no `RenderFlex` overflow artifacts, glyph/unread-dot/headline/subject/overflow-icon all present as described, matching the worker's own eyeball notes (which were explicit and accurate, unlike UNIT 09's gap). No leaked processes, clean git status.

## UNIT 11 — complete — 2026-09-14

COMMITS:
- `4d75afc19` feat(client): load per-request attention in my work
- `de01d7ed4` test(client): cover my work attention state
- `331a76bab` docs: UNIT 11 my work attention state journal

TESTS:
- `cd packages/client && dart run build_runner build -d` → exit 0
- `cd packages/client && flutter test test/features/my_work/` → **127/127 passed**
- `./scripts/check-custom-lints.sh packages/client` → `32 (baseline: 32)` — OK

FILES:
- `packages/client/lib/features/my_work/ui/bloc/my_work_state.dart`
- `packages/client/lib/features/my_work/ui/bloc/my_work_cubit.dart`
- `packages/client/lib/features/my_work/domain/use_case/my_work_case.dart`
- `packages/client/lib/domain/attention/attention_case.dart`
- `packages/client/test/features/my_work/my_work_attention_state_test.dart` (new)
- `packages/client/test/features/my_work/my_work_test_support.dart`

FINDINGS:
- Card load path uses `loadDeskInit` + `loadReviewWindows` (not legacy names from plan line refs).
- Stale attention drops reuse cubit field `_fetchSeq` (same guard as desk card fetch in `_runFetch` / `_loadArchived`).
- Chunking at 500 lives on `MyWorkCase._maxAttentionIdsPerRequest`, mirroring `HomeAttentionCubit._maxIdsPerRequest` loop shape.

DECISIONS:
- Attention fetch runs after successful desk emit and again after `_loadArchived` completes so archived beacon ids join the union.
- Failed attention sets `attentionLoaded: false` only — prior `attentionByBeacon` entries are left intact (§4.8 unknown, not empty-loaded).
- `openedBeacon` optimistically zeroes `unseenCount` only; `liveObligations` and `latestUnseen` unchanged.

REMAINING: none. Proceed to UNIT 12.

**Manager verdict: ACCEPTED.** Independently re-ran all three Verify commands (build_runner clean, 127/127 flutter test, lints 32/32 baseline). Confirmed via `git log` that `derive_my_work_cards.dart` was not touched by any commit in this unit (last touched by pre-existing, unrelated commits). The two-call attention-fetch design (once after desk load with only non-archived ids, again inside `_loadArchived`'s success path recomputing the full union once archived cards exist) is a sensible reading of "union of non-archived and archived" that avoids eagerly fetching archived-card attention on every desk load — each call still reads `state.nonArchivedCards`/`state.archivedCards` fresh at call time, so the second call genuinely covers the full union, and both are guarded by the same `_fetchSeq` staleness check the cubit already uses for card fetches. The `AttentionCase.myWorkAttention` passthrough and `MyWorkCase.loadMyWorkAttention`/`markSeenForBeacon` wiring weren't explicit in the plan's Owns list but are necessary, correctly-layered additions (`MyWorkCase` goes through `AttentionCase`, never the raw repository directly) — legitimate per §3 rule 2. Chunking at 500 mirrors the server-side guard exactly, with correct final-partial-chunk slicing. Failure path only changes `attentionLoaded`, leaving prior `attentionByBeacon` entries intact — correctly matches design §4.8's "unknown, not empty" requirement. `openedBeacon` zeroes only `unseenCount`, leaves `liveObligations`/`latestUnseen` untouched, and awaits `markSeenForBeacon` after the optimistic emit. All 5 required test scenarios present. No leaked processes, clean git status.

## UNIT 12 — complete — 2026-09-14

COMMITS:
- `34577d77d` feat(client): add my work obligation and whats-new widgets
- `61ae295c2` feat(client): show obligations and news on my work cards
- (this journal entry) docs: UNIT 12 my work card obligations journal

TESTS:
- `cd packages/client && flutter gen-l10n` → exit 0
- `cd packages/client && flutter test test/features/my_work/` → **154/154 passed**
- `./scripts/check-custom-lints.sh packages/client` → `32 (baseline: 32)` — OK
- `bash scripts/check-user-facing-terminology.sh` → OK

FILES:
- `packages/client/lib/features/my_work/ui/widget/my_work_obligation_block.dart` (new)
- `packages/client/lib/features/my_work/ui/widget/my_work_whats_new_row.dart` (new)
- `packages/client/lib/features/my_work/ui/widget/my_work_cards.dart`
- `packages/client/lib/features/my_work/ui/widget/my_work_last_event_row.dart`
- `packages/client/lib/features/my_work/ui/widget/my_work_card_metadata_row.dart`
- `packages/client/lib/ui/widget/beacon_hud_metadata_composer.dart`
- `packages/client/lib/domain/attention/attention_case.dart` (`settleReceipt`)
- `packages/client/lib/features/my_work/domain/use_case/my_work_case.dart`
- `packages/client/lib/features/my_work/ui/bloc/my_work_cubit.dart`
- `packages/client/lib/ui/test_ids.dart`
- `packages/client/l10n/app_en.arb`, `app_ru.arb`
- `packages/client/pubspec.yaml` (7.6.8 → 7.6.9), `web/index.html`
- `packages/client/test/features/my_work/my_work_obligation_block_golden_test.dart` (new)
- `packages/client/test/features/my_work/my_work_whats_new_row_test.dart` (new)
- `packages/client/test/features/my_work/goldens/my_work_obligation_block_*.png` (17)
- `packages/client/test/features/my_work/goldens/my_work_whats_new_*.png` (9)

FINDINGS:
- `AttentionCase.settle` no-ops when the receipt is not in the feed cache; My Work uses new `settleReceipt` → repository directly (same refresh side effects as feed settle).
- Actor label on obligation lines uses first-token of `title` for known `presentationKey` values (server often puts display name in title).
- Eyeballed goldens: 5-obligation collapsed (light EN) shows three Anna obligation lines with trailing Done, then “2 more” expand row; whats-new emphasis (light EN) shows semibold “3 new · I will bring tools tomorrow” single line.
- Gate off: existing **154** my_work tests unchanged in behavior (redesign widgets mount only when `readWorkActivityRedesignGateEnabled()` is true).

DECISIONS:
- Hide HUD last-event metadata when redesign gate is on so the whats-new row (muted last-event fallback) does not duplicate the metadata table row.
- Review help-offers / review CTAs move to `FilledButton.tonal` inside `MyWorkObligationBlock` when gate is on; footer CTAs for those flags are suppressed.

REMAINING: none. Proceed to UNIT 13.

**Manager verdict: ACCEPTED — real bug caught and fixed by the worker.** Independently re-ran all four Verify commands (gen-l10n clean, 154/154 flutter test, lints 32/32 baseline, terminology check OK). Confirmed `pubspec.yaml`/`web/index.html` both carry `7.6.9` consistently.

The worker discovered that `AttentionCase.settle` early-returns when the receipt isn't in `_receiptsById` (the feed-session cache) — which My Work obligations never populate, since they arrive via `myWorkAttention`, not a mounted feed session. Calling the existing `settle` from the new "Done" button would have silently done nothing. Fix reviewed in full: `settle(receiptId)` keeps its exact original cache-check-then-delegate shape (zero behavior change for existing callers), and a new public `settleReceipt(receiptId)` holds the actual mutation + refresh side effects, which both paths now share. Correct, minimal, safe.

The unplanned touch to `my_work_card_metadata_row.dart`/`beacon_hud_metadata_composer.dart` (suppressing the last-event HUD row under the gate so it doesn't duplicate the muted what's-new fallback) is equally clean: new parameter `hideLastEventMetadata` defaults `false`, and the one call site passes `readWorkActivityRedesignGateEnabled()` — with the gate off (`false`), the added `!hideLastEventMetadata &&` condition is always true, so gate-off behavior is provably unchanged.

Read the full `my_work_cards.dart` diff: every gating point is correct — `_myWorkAttentionMarker`/`hasReviewCta`/`vm.showReviewCta` conditions reduce to their exact original expressions when the gate is off; `_openBeacon`/`_openBeaconOrSelect` only call the new `openedBeacon` inside a gate-on check, the router push itself stays unconditional; `_myWorkCardAttentionSection` renders `SizedBox.shrink()` when the gate is off. Mounted consistently across all five card kinds. Personally opened the 5-obligations-collapsed golden: exactly 3 full obligation rows with trailing "Done" actions plus a shorter "2 more" row beneath — matches spec and the worker's own description, no overflow artifacts. No leaked processes, clean git status, commits well split.

## UNIT 13 — complete — 2026-09-14

COMMITS:
- `5a5385deb` feat(client): derive my work responsibility sections
- `3934228e5` feat(client): section my work by responsibility
- (this journal entry) docs: UNIT 13 my work sectioned body journal

TESTS:
- `cd packages/client && flutter gen-l10n` → exit 0
- `cd packages/client && flutter test test/features/my_work/` → **162/162 passed**
- `./scripts/check-custom-lints.sh packages/client` → `32 (baseline: 32)` — OK

FILES:
- `packages/client/lib/features/my_work/domain/derive_my_work_sections.dart` (new)
- `packages/client/lib/features/my_work/ui/screen/my_work_screen.dart`
- `packages/client/l10n/app_en.arb`, `app_ru.arb`
- `packages/client/pubspec.yaml` (7.6.9 → 7.6.10), `web/index.html`
- `packages/client/test/features/my_work/derive_my_work_sections_test.dart` (new)
- `packages/client/test/features/my_work/my_work_sectioned_body_test.dart` (new)

FINDINGS:
- Section priority when classifying: live obligation wins over `isFinishedCard` — a finished request with a live obligation appears only under **Needs you**, never Finished.
- Needs you header `count` is total live obligation receipts in that section (D4), not beacon/card count.
- Within-section order preserves the desk sort order from `visibleCards` (stable partition of an already-sorted list).

DECISIONS:
- Redesign gate suppresses obligations pane and 2:3 split even when `myWorkObligationsGate` is on; legacy tree unchanged when redesign gate is off.
- Finished section helper reuses existing `myWorkFinishedHint` (no new l10n key).

REMAINING: none. Proceed to UNIT 14.

**Editorial note (overseer):** the UNIT 13 worker's journal append split this section's own manager-verdict paragraphs across the wrong position (part landed after UNIT 13's own REMAINING line instead of staying with the rest of the UNIT 12 verdict). Restored the correct order above — no content was lost, this was a positional fix only.

**Manager verdict: ACCEPTED.** Independently re-ran all three Verify commands (gen-l10n clean, 162/162 flutter test, lints 32/32 baseline); confirmed `pubspec.yaml`/`web/index.html` both carry `7.6.10`. Read `derive_my_work_sections.dart` in full: pure, well-documented (doc comment states the exact priority: live obligation → Needs you, else finished → Finished, else In progress, matching FINDINGS), reuses the real `card.isFinishedCard` rather than reinventing, correctly handles the drafts/archived unlabeled-section case via an exhaustive `MyWorkFilter` switch. Read the `my_work_screen.dart` diff: every gate check reduces to the original expression when `redesignEnabled` is false (`!redesignEnabled && overflowMenu` inclusion, `!obligationsGateEnabled || redesignEnabled` for the 2:3-split suppression, `showFinishedHint`'s added `!redesignEnabled &&` term) — the legacy `ListView.separated` path is preserved verbatim below the new early-return, with only the per-item builder extracted into a shared `_myWorkCardTile` helper called identically from both paths (a pure refactor, not a behavior change). Section header `count` is wired from `myWorkNeedsYouObligationReceiptCount` (receipts, not cards) only for Needs You, and `helperText` from the existing `myWorkFinishedHint` only for Finished — both correct. Independently read the two most load-bearing tests: `'redesign on: first card fully visible on first paint'` pumps at 1.3× text scale with both gates on and asserts the actual rendered `Rect` of the first `MyWorkCardRouter` fits the viewport plus that `MyWorkObligationsPane` is absent — a genuine widget-level assertion, not a code read; `'redesign off: obligations pane still mounts when gate on'` asserts the legacy pane by key with the redesign gate off and the (separate) obligations gate on, directly proving the two gates don't interfere. No leaked processes, clean git status otherwise, commits well split.

## UNIT 14 — complete — 2026-09-14

COMMITS:
- `a807aea66` refactor(client): extract inbox item GraphQL fields fragment
- `8ffe28e64` feat(client): page open forwards for activity data layer
- `c5727edbb` feat(client): add activity offers cubit for pinned forwards
- `ecae0b237` test(client): cover activity offers cubit paging and live updates
- (this journal entry) docs: UNIT 14 activity offers cubit journal

TESTS:
- `cd packages/client && dart run build_runner build -d` → exit 0
- `cd packages/client && flutter test test/features/inbox/activity_offers_cubit_test.dart` → **8/8 passed**
- `./scripts/check-custom-lints.sh packages/client` → `32 (baseline: 32)` — OK

FILES:
- `packages/client/lib/features/inbox/data/gql/inbox_item_fields.graphql` (new)
- `packages/client/lib/features/inbox/data/gql/inbox_fetch.graphql`
- `packages/client/lib/features/inbox/data/gql/activity_offers.graphql` (new)
- `packages/client/lib/features/inbox/data/repository/inbox_repository.dart`
- `packages/client/lib/features/inbox/domain/use_case/inbox_case.dart`
- `packages/client/lib/features/inbox/ui/bloc/activity_offers_cubit.dart` (new)
- `packages/client/lib/features/inbox/ui/bloc/activity_offers_state.dart` (new)
- `packages/client/test/features/inbox/activity_offers_cubit_test.dart` (new)
- `packages/client/test/features/inbox/inbox_case_test.dart`

FINDINGS:
- Ferry codegen emits shared `GInboxItemFields` so InboxFetch and ActivityOffers rows map through one `_mapInboxItemRows` helper.
- Plan names `deskRelevantChanges` / `helpOfferChanges` match `InboxCase` getters at `inbox_case.dart:49-73` (unchanged names).

DECISIONS:
- Demotion signal for UNIT 17: `ActivityOffersCubit.demotedBeaconIds` as `Stream<String>` (beacon id), not a sealed effect type.
- `loadFirst()` loads page rows and aggregate count in parallel so count failures set `countLoadFailed` without coercing to `0`.
- Held-back live arrivals store full `InboxItem` in cubit-private maps; state exposes `heldBackIds` only for pill count.
- `InboxCubit` left untouched (still feeds Watching / Rejected / legacy Activity UI).

REMAINING: none. Proceed to UNIT 15.

**Manager verdict: ACCEPTED.** Independently re-ran all three Verify commands (build_runner clean, 8/8 flutter test, lints 32/32 baseline). Confirmed via `git diff --stat` against the pre-unit HEAD that `inbox_cubit.dart` was not touched at all. The `$userId` variable declared-but-unused in `activity_offers.graphql` matches a pre-existing convention already present in `inbox_fetch.graphql` (Hasura's row permission does the actual scoping; the variable isn't a new oddity this unit introduced). Read the full `ActivityOffersCubit` implementation: `loadFirst()` fetches the page and count in parallel with independent try/catch, nulling `totalCount` AND setting `countLoadFailed` on failure (doubly distinguishing failure from zero); `loadMore()` uses the last item's `(latestForwardAt, beaconId)` as the next cursor with a defensive de-dupe on merge; `_upsertOpenForward`/`_demoteBeacon` correctly move ids between `items` and the held-back bucket depending on `_scrolledAway`, and `_demoteBeacon` only emits on `demotedBeaconIds` when the beacon was actually present (no spurious signals); `_refreshUnseenDots` chunks at 500 with its own generation guard, independent of the page-load generation. Two nice, safe additions beyond the literal ask: a 50ms per-beacon debounce on realtime-triggered refetches, and a separate lightweight `ActivityOffersCount` query used for the live "refresh totalCount on every change" path instead of re-paging. Verified the tie-break test's `_PagingRepo` fake genuinely implements keyset-cursor slicing (locates the `(cursorAt, cursorBeaconId)` row and returns everything after it) rather than returning canned pages — a real test, not a vacuous one. All 8 tests map 1:1 to the plan's required scenarios. No leaked processes, clean git status, commits well split (fragment extraction as its own commit).

## UNIT 15 — complete — 2026-09-14

COMMITS:
- `b27369bff` refactor(client): extract inbox card actions for reuse
- `398e3cbd2` feat(client): add activity forward and digest copy keys
- `5d024a80f` feat(client): add activity offer, forward, and digest rows
- `cdcf36a4d` test(client): golden-test activity offer and forward rows
- (this journal entry) docs: UNIT 15 activity offer and stream rows journal

TESTS:
- `cd packages/client && flutter gen-l10n` → exit 0
- `cd packages/client && flutter test test/features/inbox/` → **87/87 passed**
- `./scripts/check-custom-lints.sh packages/client` → `32 (baseline: 32)` — OK
- `bash scripts/check-user-facing-terminology.sh` → OK

FILES:
- `packages/client/lib/features/inbox/ui/widget/inbox_card_actions.dart` (new, from triage list)
- `packages/client/lib/features/inbox/ui/widget/inbox_triage_list.dart`
- `packages/client/lib/features/inbox/ui/screen/inbox_watching_screen.dart`
- `packages/client/lib/features/inbox/ui/widget/activity_offer_bounded_shell.dart` (new)
- `packages/client/lib/features/inbox/ui/widget/activity_offer_card.dart` (new)
- `packages/client/lib/features/inbox/ui/widget/activity_forward_row.dart` (new)
- `packages/client/lib/features/inbox/ui/widget/activity_watching_digest_row.dart` (new)
- `packages/client/lib/features/inbox/ui/widget/inbox_forward_attribution_copy.dart` (new)
- `packages/client/lib/features/inbox/ui/widget/activity_forward_outcome_copy.dart` (new)
- `packages/client/lib/features/updates/ui/widget/invite_accepted_receipt_card.dart`
- `packages/client/lib/ui/test_ids.dart`
- `packages/client/l10n/app_en.arb`, `app_ru.arb`
- `packages/client/test/features/inbox/activity_offer_card_golden_test.dart` (new)
- `packages/client/test/features/inbox/activity_forward_row_golden_test.dart` (new)
- `packages/client/test/features/inbox/goldens/activity_*.png` (34)

FINDINGS:
- `activity-prompt-pin-$receiptId` already existed on `TestIds.activityPromptPin`; prompt variant keeps it via `KeyedSubtree`.
- Stream forward rows have no forwarder name on the server payload yet (`body` empty); row headline uses `receipt.body` as sender name when present, else title only — goldens pass sender via `body`.
- Forward-row relay phrasing reuses `inboxFromForwarder` / `inboxFromForwarderPlus` (offer why-line) rather than a new «переслал(а)» key.
- Eyeballed goldens: `activity_offer_card_forward_with_help_light_en.png` shows dismiss ✕, avatar, two-line title, “From Anna +2” why-line, unseen dot, age, tonal Offer Help, Forward, Watch; `activity_forward_row_helping_light_en.png` shows send glyph, “Garden cleanup — From Gleb”, outcome “You’re helping”, age.
- Forward offer card at 1.3× text scale stays ≤ 180 logical px (asserted in test).

DECISIONS:
- `ActivityOfferBoundedShell` shared by forward offers and `InviteAcceptedReceiptCard` (`activityOfferBoundedShell: true`) to avoid duplicating prompt setup logic.
- `ActivityWatchingDigestRow` has no golden in this unit (plan goldens focused on offer card + forward outcomes); widget is thin wrapper over `TenturaAttentionSummaryRow`.

REMAINING: none. Proceed to UNIT 16 (mount widgets in `ActivityStreamView`).

**Manager verdict: ACCEPTED.** Independently re-ran all four Verify commands (gen-l10n clean, 87/87 flutter test, lints 32/32 baseline, terminology OK). Confirmed the `inbox_card_actions.dart` extraction landed as its own isolated commit (3 files, pure move, no other unit's changes mixed in). Confirmed the `≤ 180` height assertion is a real programmatic check (`expect(box.size.height, lessThanOrEqualTo(180))`), not just a claim. Personally eyeballed three goldens: the 1.3×-scale forward offer card is compact with dismiss/avatar/title/why-line/actions all present and no overflow; the watching forward-row and not-interested forward-row (RU) show correctly differentiated per-outcome content — the not-interested row alone carries the blue "Вернуть" restore action, confirming outcome-specific action wiring is correct. The disclosed `body`-empty gap (synthetic forward items from UNIT 03 don't yet carry a forwarder-name field, so "From X" attribution will be blank on real data until a future unit adds it) is an honestly-flagged limitation of the server's current synthetic-item shape, not a defect in this unit's own delivered scope — noted for UNIT 22's final acceptance walkthrough. `activity-prompt-pin-$receiptId` was correctly verified to already exist (`TestIds.activityPromptPin`) rather than assumed. No leaked processes, clean git status, commits well split with the pure refactor landing first as instructed.

## UNIT 16 — complete — 2026-09-14

COMMITS:
- `b645cdf07` feat(client): add activity for-you copy for stream header
- `fbf7db1cd` feat(client): make activity one stream of offers
- `9ce1dc99b` feat(client): mount activity stream under redesign gate
- `9684e601d` test(client): cover activity stream view assembly
- (this journal entry) docs: UNIT 16 activity stream view journal

TESTS:
- `cd packages/client && flutter gen-l10n` → exit 0
- `cd packages/client && flutter test test/features/inbox/ test/features/updates/` → **180/180 passed** (includes 6 new `activity_stream_view_test.dart` cases)
- `./scripts/check-custom-lints.sh packages/client` → `32 (baseline: 32)` — OK

FILES:
- `packages/client/lib/features/inbox/ui/widget/activity_stream_view.dart` (new)
- `packages/client/lib/features/inbox/ui/screen/inbox_screen.dart`
- `packages/client/l10n/app_en.arb`, `app_ru.arb`
- `packages/client/lib/ui/test_ids.dart`
- `packages/client/pubspec.yaml` (7.6.10 → 7.6.11), `web/index.html`
- `packages/client/test/features/inbox/activity_stream_view_test.dart` (new)

FINDINGS:
- **Server-side open-forward / receipt overlap:** UNIT 03 dedupes `relay_received` receipts when an inbox row exists on the activity surface; open forwards never appear as stream receipts server-side. Client only lifts invite prompts from the stream via `computeInvitePromptPinPlacement` (`liftedReceiptIds`) — no extra client dedupe for open offers was added.
- `ActivityOffersCubit` must finish `loadFirst()` before mounting `UpdatesFeedCubit` in widget tests; constructing both concurrently against one `AttentionCase` can deadlock `loadFirst()` in the test zone.
- Invite prompt pin eligibility requires `presentationPayloadJson.inviteOrigin == "new_account"` (existing `receiptNeedsInvitePromptProjection` rule).

DECISIONS:
- Pinned-zone `loadFirst()` runs from `InboxScreen`'s `ActivityOffersCubit` provider; the view only wires scroll → `setScrolledAway` (threshold 180 logical px, UNIT 15 card bound) for UNIT 17.
- Stream receipt exclusion: rely on server activity-surface feed + prompt `liftedReceiptIds` only (see FINDINGS).
- Per-source failure: offers use inline retry row; stream keeps `UpdatesRefreshErrorBanner` — neither blocks the other.

REMAINING:
- UNIT 18: Activity chrome (title, mark-all scoped to activity, notification history route).
- UNIT 19: nav indicators / surface-aware open.

**Environment note:** two leaked processes from this worker's own verification runs were still alive well after the worker itself exited — an orphaned `rg` pipeline (PID 44759/44760, watching test output) and a live `flutter test test/features/inbox/activity_stream_view_test.dart` process tree (44758 + `frontend_server_aot` + `flutter_tester` children). Both killed by the overseer before review. Not a correctness issue, just cleanup hygiene.

**Manager verdict: ACCEPTED — the largest unit in the plan, held up well.** Independently re-ran all three Verify commands (gen-l10n clean, 180/180 flutter test, lints 32/32 baseline). The server-side-exclusion question from the prompt was answered correctly and with real investigation: UNIT 03 already excludes open forwards from the activity-surface receipt stream server-side and dedupes `relay_received` receipts into the forward representation, so no redundant client-side dedup was needed for offers — the worker correctly kept only the pre-existing `computeInvitePromptPinPlacement`/`liftedReceiptIds` mechanism, which is a distinct concern (invite prompts, not open forwards). Read the two most load-bearing tests in full: `'stream pagination waits until offers hasMore is false'` genuinely exercises the pinned-then-stream sequencing (flings to bottom, confirms the offers source pages first via call counts, then exhausts the offers pages and confirms the stream source only THEN starts paginating); `'60 offers and 120 stream items scroll without duplicate keys'` checks for duplicate visible keys after EVERY one of 80 incremental scroll passes, not just the final state — stronger than what was asked. The gate-mounting diff in `inbox_screen.dart` is a clean early-return: gate on returns `ActivityStreamView`, gate off falls through unconditionally to the exact untouched legacy `Column` body. `setScrolledAway`/`demotedBeaconIds` wiring is left cleanly in place for UNIT 17 to build on, as instructed, without extra unrequested behavior. No leaked processes remain (see environment note above), clean git status, commits well split.

## UNIT 17 — complete — 2026-09-14

COMMITS:
- `5aea8f17c` feat(client): add activity live arrival and demotion copy
- `0ef8237c5` feat(client): demote answered forwards into the stream
- `aa34780b7` test(client): cover activity live arrival and demotion motion
- `6369aff86` docs: UNIT 17 live arrival and demotion motion journal

TESTS:
- `cd packages/client && flutter gen-l10n` → exit 0
- `cd packages/client && flutter test test/features/inbox/activity_live_motion_test.dart` → **5/5 passed**
- `cd packages/client && flutter test test/features/inbox/` → **98/98 passed**
- `cd packages/client && flutter test test/features/updates/` → **87/87 passed**
- `./scripts/check-custom-lints.sh packages/client` → `32 (baseline: 32)` — OK

FILES:
- `packages/client/lib/features/inbox/ui/bloc/activity_offers_cubit.dart`
- `packages/client/lib/features/inbox/ui/bloc/activity_offers_state.dart`
- `packages/client/lib/features/inbox/ui/widget/activity_stream_view.dart`
- `packages/client/l10n/app_en.arb`, `app_ru.arb`
- `packages/client/lib/ui/test_ids.dart`
- `packages/client/pubspec.yaml` (7.6.11 → 7.6.12), `web/index.html`
- `packages/client/test/features/inbox/activity_live_motion_test.dart` (new)

FINDINGS:
- Overseer pre-fixes (not this worker): removed a FakeAsync `_boot()` delay loop that never called `tester.pump()`; changed the scrolled-away layout reference from `activityForYouHeader` (scrolled off-screen) to `activityOffer('fill-2')`.
- Snackbar copy is rendered via `showSnackBar` → `RichText`/`TextSpan`, so `find.text('Перемещено в ленту')` misses; tests assert `SnackBar` + `RichText.toPlainText()` instead.
- Pre-scroll by −1200px before Watch tapped `B-far` off the top (lazy list → 0 widgets); scenario fixed by watching at offset 0 while the demoted forward row remains deep in the combined pinned + stream list (snackbar path).
- `_scrollToForwardBeacon` now steps/jumps the `ScrollController` when the forward row receipt exists but the lazy row is not built yet; tests use `disableAnimations` + `SnackBarAction.onPressed()` (snackbar below the 400px surface) and `scrollUntilVisible` only if the row is still off-screen after the action increases scroll offset.

DECISIONS:
- `pendingMovedToStreamBeaconId` + `stageMovedToStreamNudge` / `clearMovedToStreamNudge` on `ActivityOffersCubit` (view-owned snackbar, cubit-owned pending flag).
- Held-back pill uses `activityNewItemsPill` / `TestIds.activityNewItemsPill`; moved nudge uses `activityMovedToStream` / `activityShowInStream`.

REMAINING: none. Proceed to UNIT 18.

**Process note (overseer):** the first attempt at this unit hit the 1-hour hard timeout (exit 124) without committing anything. Diagnosis: (1) six overlapping `flutter test` invocations had piled up in the background since the worker never confirmed a previous run had exited before starting the next — killed all before proceeding; (2) the real root cause of the hang was a bare `for (...) await Future<void>.delayed(...)` loop inside `_boot()`, called directly in a `testWidgets()` body — `testWidgets` runs in a FakeAsync zone where the virtual clock only advances via `tester.pump()`, so an un-pumped `Future.delayed` never resolves. Fixed directly (deleted the loop — nothing depended on it) along with one related test bug (a reference widget used to prove "no layout shift" was itself scrolled out of view by the test's own setup). A second, narrowly-scoped recovery worker fixed the one remaining genuine test-scenario bug (tapping "Watch" on a card already scrolled off-screen) and completed the unit's commits/journal from a clean, informed brief.

**Manager verdict: ACCEPTED.** Independently re-ran the full Verify block plus a regression check (5/5 `activity_live_motion_test.dart`, 98/98 `test/features/inbox/`, 87/87 `test/features/updates/`, lints 32/32 baseline, gen-l10n clean) after confirming zero leaked test processes beforehand. Read `_scrollToForwardBeacon` in full: bounded on every axis that matters — a hard 40-pass cap, a `mounted` check, `hasNextPage` gating further page loads, and `position.pixels < position.maxScrollExtent` gating the manual step-scroll fallback for the lazy-list-not-yet-built edge case — no infinite-loop risk. The `pendingMovedToStreamBeaconId` / `stageMovedToStreamNudge` split (cubit owns the pending flag, view owns the actual SnackBar) is a clean, correctly-layered design. Version bump (`7.6.12`) consistent between `pubspec.yaml` and `web/index.html`. Fixed a recurring journal-ordering artifact (the recovery worker's append again displaced the UNIT 16 manager-verdict paragraph, as UNIT 13's worker once did) — restored, no content lost. No leaked processes, clean git status, commits focused (copy, feature, tests, journal).

## UNIT 18 — complete — 2026-09-14

COMMITS:
- `002ba4fc9` feat(client): add notification history route and screen
- `faeed8311` feat(client): activity chrome behind redesign gate
- `95ad63faf` test(client): cover activity chrome and notification history
- (this journal entry) docs: UNIT 18 activity chrome and history journal

TESTS:
- `cd packages/client && dart run build_runner build -d` → exit 0
- `cd packages/client && flutter gen-l10n` → exit 0
- `cd packages/client && flutter test test/features/inbox/activity_chrome_test.dart test/features/updates/notification_history_screen_test.dart` → **8/8 passed**
- `./scripts/check-custom-lints.sh packages/client` → `32 (baseline: 32)` — OK

FILES:
- `packages/client/lib/consts.dart`
- `packages/client/lib/app/router/root_router.dart`
- `packages/client/lib/features/inbox/ui/screen/inbox_screen.dart`
- `packages/client/lib/features/updates/ui/screen/updates_screen.dart`
- `packages/client/l10n/app_en.arb`, `app_ru.arb`
- `packages/client/pubspec.yaml` (7.6.12 → 7.6.13), `web/index.html`
- `packages/client/test/features/inbox/activity_chrome_test.dart` (new)
- `packages/client/test/features/updates/notification_history_screen_test.dart` (new)

FINDINGS:
- `UpdatesRoute` was already generated in `root_router.gr.dart` but unregistered until this unit; `kPathUpdates` redirect left unchanged for UNIT 20.
- Activity scroll restoration after history back is not asserted here: it depends on `PageStorageKey` + real stack pop via AutoRoute; widget tests use a mock router without a nested navigator, so that behavior is deferred (likely integration or UNIT 19+).
- Gated mark-all-seen reads `AttentionCase.surfaceSummary` (`activityUnreadTotal`), not feed-session `unreadTotal`, so it stays correct when the stream body is activity-scoped.

DECISIONS:
- History overflow entry and mark-all button only when `readWorkActivityRedesignGateEnabled()`; gate-off overflow unchanged.
- `openNotificationHistory` pushes `UpdatesRoute` (same as plan’s generated route type).

REMAINING: none. Proceed to UNIT 19.

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
| 10 | complete (accepted) |
| 11 | complete (accepted) |
| 12 | complete (accepted, real bug caught + fixed by worker) |
| 13 | complete (accepted) |
| 14 | complete (accepted) |
| 15 | complete (accepted) |
| 16 | complete (accepted) |
| 17 | complete (accepted, hang diagnosed+fixed by overseer) |
| 18 | complete |
| 19 | pending |
| 20 | pending |
| 21 | pending |
| 22 | pending |

## Unresolved decisions and blockers

None yet.
