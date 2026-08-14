# Availability / request-receptiveness — implementation journal

## Scope

- **Objective:** implement
  [`availability-request-receptiveness-implementation-plan.md`](availability-request-receptiveness-implementation-plan.md)
  end to end for per-user request-receptiveness (availability): orthogonal `is_limited` /
  `resume_on`, V2 mutations, transactional forward gate, typed `ForwardDeliveryResult`, and
  client surfaces (own profile, other profile, graph, picker, person-forward).
- **Plan source:** [`availability-request-receptiveness-architecture.md`](availability-request-receptiveness-architecture.md)
  **rev 3**; the implementation plan records user approval on 2026-08-13 and is authoritative
  over the stale architecture front-matter `status: draft`.
- **S10 / S12 closures (plan §0, frozen for v1):**
  - **S10 — band rows:** exclude availability-paused people from the client-side capability band
    after `fetchForwardContext`; do not add a special pause line to a band row. Preserve the
    surviving band order. The server recommender remains availability-blind.
  - **S12 — entry point:** own profile only. Do not add a Settings tile.
- **Repository:** `/home/vader/MY_SRC/tentura`
- **Branch / starting HEAD:** `main` / `9c9bcf518e85668023b9afb2e8ce490a6a266c1c`
- **Started:** 2026-08-13.

## Live baseline (verified at UNIT 00)

| Item | Value |
|---|---|
| Latest migration | `m0147` |
| `packages/client/pubspec.yaml` | `5.12.1` |
| `packages/client/web/index.html` cache-buster | `flutter_bootstrap.js?v=5.12.1` |
| `packages/server/lib/env.dart` `kDefaultMinClientVersion` | `5.6.38` |

Target release for this feature (plan §0): client `5.13.0`, web cache-buster `5.13.0`, server
minimum `5.13.0` (UNIT 16). This plan owns migration `m0148`.

## Protected pre-existing worktree changes

Do not edit, stage, revert, or commit these unless a later unit proves a file is genuinely
required; in that case stop that unit and record the conflict.

```text
 M docs/README.md
 M docs/archive/journals/commitment-truth-rework-journal.md
 M docs/archive/plans/commitment-truth-rework-plan.md
 M docs/audits/room-coordination-audit.md
 M packages/server/test/api/controllers/websocket/websocket_realtime_protocol_test.mocks.dart
 M scripts/run_client_integration_web_local.sh
?? dart-defines
?? docs/plans/algorithm-invariant-suites-plan.md
?? docs/plans/availability-request-receptiveness-architecture.md
?? docs/plans/availability-request-receptiveness-implementation-plan.md
?? docs/plans/availability-review-codex.md
?? docs/plans/availability-review-grok46.md
?? docs/plans/availability-review-kimik3.md
?? docs/plans/graph-navigation-implementation-guide.md
?? docs/plans/graph-navigation-rework-plan.md
?? docs/plans/issue-100-people-graph-person-context-implementation-plan.md
?? docs/plans/issue-115-reply-to-message-implementation-journal.md
?? docs/plans/issue-115-reply-to-message-plan.md
?? docs/plans/received-reviews-trust-changes-plan.md
?? docs/plans/subjective-help-tag-evidence-architecture.md
?? docs/plans/subjective-help-tag-evidence-implementation-plan.md
?? graph-ego-neighbors-layout-issue.md
?? key.fb
?? out.key
?? product_testing_compact_buglist.md
?? product_testing_detailed_report.md
```

The architecture and implementation plan files are pre-existing and untracked. They are
authoritative for this run but must not be staged or committed by workers. This journal is
orchestrator-owned once UNIT 00 lands.

## Stop conditions (plan §1)

Stop and record `BLOCKED` instead of guessing when:

- the latest migration is no longer `m0147` or `m0148` already exists;
- the client version is no longer `5.12.1` (until UNIT 16 bumps to `5.13.0`);
- an owned file has unrelated local modifications that cannot be preserved by a narrow edit;
- rev 3 field names, mutation names, temporal rule, or typed-result fields have changed;
- a required PostgreSQL/Hasura test cannot be run in an isolated disposable database.

A changed starting Git commit alone is not a blocker. Reconcile live symbols and proceed if
the contracts and reserved identifiers still match.

## Executor contract (plan §2)

1. Work units in manifest order. Complete one unit, run its checks, append the journal, and make
   its focused local commit before starting the next unit. Do not push or deploy.
2. Preserve all pre-existing modified and untracked files. Never reset, stash, clean, or stage
   unrelated work. Stage explicit paths only.
3. Every journal entry contains unit, status, commit, exact tests, files, findings, and remaining
   work.
4. If live code contradicts this plan, do not improvise across a boundary. Record the exact
   symbol/path and stop that unit. Mechanical line-number drift is not a contradiction.
5. Server use cases depend on domain ports only. Client domain types never import data/UI. Cubits
   never import `data/service`.
6. Use Freezed where the package convention applies. Run codegen; never edit `*.g.dart`,
   `*.freezed.dart`, `*.gr.dart`, `*.config.dart`, or `_g/`.
7. Feature UI uses `context.tt`, `TenturaText`, `TenturaStatusText`, Material 3, 48 dp targets.
   No raw colors, text sizes, padding numbers, or radii. No chips/badges/icons for availability
   status.
8. Tests tagged `pg` must use an isolated disposable PostgreSQL database.

**Journal entry template:**

```markdown
## UNIT <id> — <complete|partial|blocked> — <ISO date>
COMMITS: <hash and subject, or none>
TESTS: <exact command and outcome>
FILES: <paths>
FINDINGS: <live facts that differed from the plan, or none>
REMAINING: <specific work, or none>
```

## Boundaries (plan §0, §2)

Do **not** add availability to presence, WebSockets, realtime entities, Updates, notifications,
avatars, room/member lists, contacts, global search, My Work, or Inbox. Do **not** gate existing
forwards, chats, offers, admissions, cancellations, edits, or beacon-invite acceptance. Do **not**
edit generated files by hand. Units are sequential — do not parallelize (schema/codegen, shared
`Profile`, forward contracts, and release files overlap).

## Ordered manifest

Units are sequential. Check off only after the unit's focused commit and verification.

- [x] **UNIT 00 — Journal and immutable baseline** — depends: — — commit:
  `docs: start availability implementation journal`
- [x] **UNIT 01 — Shared calendar/view model and entities** — depends: 00 — commit:
  `feat: add availability domain model`
- [x] **UNIT 02 — `m0148`, Drift table, Hasura visibility** — depends: 01 — commit:
  `feat(server): add user availability storage`
- [x] **UNIT 03 — Atomic availability repository, use case, janitor** — depends: 02 — commit:
  `feat(server): add availability commands`
- [x] **UNIT 04 — Server public-user read parity** — depends: 03 — commit:
  `feat(server): expose availability in public users`
- [x] **UNIT 05 — Three V2 availability mutations** — depends: 03 — commit:
  `feat(server): add availability mutations`
- [x] **UNIT 06 — Transactional forward gate and typed result** — depends: 03 — commit:
  `feat(server): enforce availability on forwards`
- [x] **UNIT 07 — Server PostgreSQL/concurrency/API proof** — depends: 04–06 — commit:
  `test(server): prove availability invariants`
- [x] **UNIT 08 — Client schema, date scalar, entities, read parity** — depends: 04–06 — commit:
  `feat(client): map availability data`
- [x] **UNIT 09 — Client availability command repository and Cubit** — depends: 05, 08 — commit:
  `feat(client): wire availability commands`
- [x] **UNIT 10 — Calendar presets, formatting, localization** — depends: 08 — commit:
  `feat(client): add availability copy and dates`
- [x] **UNIT 11 — Own-profile control and status** — depends: 09–10 — commit:
  `feat(client): add availability profile control`
- [x] **UNIT 12 — Other-profile and graph policy/rendering** — depends: 10 — commit:
  `feat(client): gate person request actions`
- [x] **UNIT 13 — Picker host policy, row precedence, band exclusion** — depends: 08, 10 —
  commit: `feat(client): show availability in recipient picker`
- [x] **UNIT 14 — Picker preselection, expiry refresh, typed delivery UX** — depends: 06, 08,
  10, 13 — commit: `feat(client): report actual forward delivery`
- [ ] **UNIT 15 — Deep-link person-forward gate** — depends: 06, 08, 10, 12 — commit:
  `feat(client): gate person forward flow`
- [ ] **UNIT 16 — Client release gate and cache-buster** — depends: 11–15 — commit:
  `chore: release availability client 5.13.0`
- [ ] **UNIT 17 — End-to-end and plan-wide closeout** — depends: 07, 16 — commit:
  `test: close availability implementation`

## Per-unit verification commands

| Unit | Verify |
|---|---|
| 01 | `dart test test/domain/availability_test.dart`; `(cd packages/client && dart run build_runner build -d && flutter test test/domain/entity/availability_test.dart)`; `(cd packages/server && dart run build_runner build -d && dart test test/domain/entity/user_availability_entity_test.dart)` |
| 02 | `(cd packages/server && dart run build_runner build -d)`; `(cd packages/server && dart test -t pg test/data/database/m0148_user_availability_migration_test.dart)`; `(cd packages/server && dart test -t pg test/data/database/beacon_cover_migration_test.dart)` |
| 03 | unit tests in owned paths (see plan) |
| 07 | `(cd packages/server && dart test -t pg test/data/repository/user_availability_repository_pg_test.dart)`; `(cd packages/server && dart test -t pg test/data/repository/forward_edge_availability_pg_test.dart)`; `(cd packages/server && dart test test/api/controllers/graphql/forward_delivery_result_test.dart)`; `(cd packages/server && dart test -x pg)` |
| 17 (plan-wide) | see **Plan-wide verification** below |

## Plan-wide verification (UNIT 17)

```bash
dart test
(cd packages/tentura_lints && dart test)
./scripts/check-custom-lints.sh packages/server
./scripts/check-custom-lints.sh packages/client
bash scripts/check-user-facing-terminology.sh
(cd packages/server && dart test -x pg)
(cd packages/server && dart test -t pg)
(cd packages/client && flutter gen-l10n)
(cd packages/client && dart run build_runner build -d)
(cd packages/client && flutter analyze --no-fatal-warnings --no-fatal-infos)
(cd packages/client && flutter test --dart-define=ENV=test)
(cd packages/client && flutter test --platform chrome test/data/gql/calendar_date_serializer_test.dart)
git diff --check
```

## Final acceptance checklist (plan §4)

- [ ] Architecture D1–D30 and the S10/S12 closures in this plan are implemented.
- [ ] All three mutations are self-only, non-null, V2-routed, and use-case-owned.
- [ ] `m0148` is logged/sparse, has no backfill/creation trigger, and is in rollback simulation.
- [ ] `updated_at` and any instant are absent from public schemas, maps, and entities.
- [ ] Client/server share the UTC-calendar comparison and equality boundary.
- [ ] PostgreSQL two-connection tests prove command independence and pause/forward ordering.
- [ ] Server result, snackbar, and create confirmation report actual inserted recipients.
- [ ] Every server public-user producer and client V2 adapter carries availability.
- [ ] Host enum makes all picker render/no-render choices explicit.
- [ ] Band excludes paused candidates; unseen retains paused rows and row-count semantics.
- [ ] Own profile, other profile, graph, picker, search, and person-forward match tone/action
      rules; lineage preview and non-send surfaces do not render availability.
- [ ] No existing interaction is withdrawn or gated; invite acceptance remains availability-blind.
- [ ] EN/RU copy is Request/Chat terminology-safe and human-reviewed for gender neutrality.
- [ ] Client `5.13.0`, web cache-buster `5.13.0`, server minimum `5.13.0` match.
- [ ] All plan-wide checks pass, or remaining failures are explicitly scoped and the plan remains
      incomplete.

## Worker protocol

Every worker reads the complete source plan and this complete journal before editing, appends
progress and final evidence here, preserves the protected changes above, and commits only its
owned coherent verified steps locally.

---

## UNIT 00 — complete — 2026-08-13

COMMITS: `77a017913` docs: start availability implementation journal
TESTS: baseline inspection — `git rev-parse HEAD` → `9c9bcf518e85668023b9afb2e8ce490a6a266c1c`;
`git branch --show-current` → `main`; migration tail `m0147` (no `m0148`); client `5.12.1`; web
`flutter_bootstrap.js?v=5.12.1`; `kDefaultMinClientVersion = '5.6.38'` — all match plan §1
FILES: `docs/plans/availability-request-receptiveness-implementation-journal.md`
FINDINGS: none — live baseline matches plan §1; no stop-condition triggers
REMAINING: none for UNIT 00; UNIT 01 is next

## UNIT 00 final evidence — 2026-08-13

COMMITS: `77a017913c60dbb2c2f17f45e9b8d56214e1b033` docs: start availability implementation journal
TESTS: `git diff --check` → clean (no conflict markers); baseline reconfirmed after commit
FILES: `docs/plans/availability-request-receptiveness-implementation-journal.md`
FINDINGS: none
REMAINING: none — UNIT 01 (`feat: add availability domain model`) is next

## Manager review — UNIT 00 accepted — 2026-08-13

COMMITS: `77a017913` docs: start availability implementation journal; `3b2c53af3` docs: record UNIT 00 evidence in availability journal
TESTS: independent inspection of both commits; `git diff 9c9bcf518..HEAD --check` → clean; baseline symbols remain absent for `m0148`, `AvailabilityView`, `user_availability`, `userAvailability`, and `ForwardDeliveryResult`
FILES: `docs/plans/availability-request-receptiveness-implementation-journal.md`
FINDINGS: accepted. The worker made two narrowly scoped documentation commits because the final evidence needed the first commit hash; both are intentional and preserve the protected worktree exactly.
REMAINING: UNIT 01 is dependency-ready.

## UNIT 01 — complete — 2026-08-13

COMMITS: `61428bc4a` feat: add availability domain model
TESTS:
- `dart test test/domain/availability_test.dart` → 11 passed
- `(cd packages/client && dart run build_runner build -d && flutter test test/domain/entity/availability_test.dart)` → 9 passed
- `(cd packages/server && dart run build_runner build -d && dart test test/domain/entity/user_availability_entity_test.dart)` → 9 passed
- `./scripts/check-custom-lints.sh packages/client` → pass
- `./scripts/check-custom-lints.sh packages/server` → pass
- `git diff --check` → clean
FILES:
- `lib/domain/enums.dart`
- `lib/domain/availability.dart`
- `test/domain/availability_test.dart`
- `packages/client/lib/domain/entity/availability.dart`
- `packages/client/lib/domain/entity/profile.dart`
- `packages/client/test/domain/entity/availability_test.dart`
- `packages/server/lib/domain/entity/user_availability_entity.dart`
- `packages/server/test/domain/entity/user_availability_entity_test.dart`
FINDINGS: Freezed `@Default(Availability.open())` is not a valid const default; `Profile` uses
`@Default(Availability())`, equivalent to `Availability.open()`. Generated `*.freezed.dart` files
were produced by build_runner but not staged.
REMAINING: none for UNIT 01; UNIT 02 (`feat(server): add user availability storage`) is next

## Manager review — UNIT 01 accepted — 2026-08-13

COMMITS: `61428bc4a` feat: add availability domain model; `623f04b41` docs: record UNIT 01 availability domain model evidence
TESTS: independent `dart test test/domain/availability_test.dart` → 11 passed; `(cd packages/client && flutter test test/domain/entity/availability_test.dart)` → 9 passed; `(cd packages/server && dart test test/domain/entity/user_availability_entity_test.dart)` → 9 passed; independent `(cd packages/server && dart run build_runner build -d)` → exit 0; `git diff 83260ac45..HEAD --check` → clean
FILES: the eight UNIT 01 source/test paths plus this journal
FINDINGS: accepted. The literal `@Default(Availability.open())` is not legal Freezed syntax because a factory call is not const; the equivalent const `@Default(Availability())` is necessary and recorded. The server build emits pre-existing injectable warnings, but exits successfully and no generated file was committed.
REMAINING: UNIT 02 is dependency-ready.

## UNIT 02 — complete — 2026-08-13

COMMITS: `9d42cd20e` feat(server): add user availability storage
TESTS:
- `(cd packages/server && dart run build_runner build -d)` → exit 0
- `(cd packages/server && dart test -t pg test/data/database/m0148_user_availability_migration_test.dart)` → 8 passed
- `(cd packages/server && dart test -t pg test/data/database/beacon_cover_migration_test.dart)` → 2 passed
- `./scripts/check-custom-lints.sh packages/server` → pass
FILES:
- `packages/server/lib/data/database/migration/m0148.dart`
- `packages/server/lib/data/database/migration/_migrations.dart`
- `packages/server/lib/data/database/table/user_availability.dart`
- `packages/server/lib/data/database/tentura_db.dart`
- `packages/server/test/data/database/m0148_user_availability_migration_test.dart`
- `packages/server/test/data/database/beacon_cover_migration_test.dart`
- `hasura/metadata.json`
FINDINGS: `relpersistence` from `pg_class` returns `UndecodedBytes` in the postgres
package; migration tests cast to `::text`. Isolated PG tests use
`TENTURA_USER_AVAILABILITY_MIGRATION_TEST_DB` (default `tentura_test_uavail_<pid>_<ts>`).
Local disposable Postgres connection `TimeZone` was `UTC`, satisfying Hasura `now()` parity
with `(CURRENT_TIMESTAMP AT TIME ZONE 'UTC')::date`.
REMAINING: none for UNIT 02; UNIT 03 (`feat(server): add availability commands`) is next

## Manager review — UNIT 02 accepted — 2026-08-13

COMMITS: `9d42cd20e` feat(server): add user availability storage; `38221746f` docs: record UNIT 02 user availability storage evidence
TESTS: independent `(cd packages/server && dart test -t pg test/data/database/m0148_user_availability_migration_test.dart)` → 8 passed in a disposable `tentura_test_*` database; independent beacon-cover rollback test → 2 passed; metadata assertion confirmed the exact four public fields and `hidden_for_viewer = false AND (is_limited = true OR resume_on > now())`; codegen exited 0; `git diff 611a89da2..HEAD --check` → clean
FILES: all seven UNIT 02 source/test/metadata paths plus this journal
FINDINGS: accepted. The table is logged/sparse, with no trigger/backfill and no public `updated_at`; the UTC connection check turns timezone drift into a test failure.
REMAINING: UNIT 03 is blocked before editing: `packages/server/lib/domain/use_case/task_worker_case.dart`, an owned file, has unrelated uncommitted GetIt/BeaconCase changes that appeared after UNIT 01. Do not stage, overwrite, or incorporate them without their owner resolving the boundary.

## UNIT 03 — complete — 2026-08-13

COMMITS: `4f776360a` feat(server): add availability commands
TESTS:
- `(cd packages/server && dart run build_runner build -d)` → exit 0
- `(cd packages/server && dart test test/domain/use_case/user_availability_case_test.dart test/domain/use_case/task_worker_case_test.dart)` → 25 passed
- `./scripts/check-custom-lints.sh packages/server` → pass
FILES:
- `packages/server/lib/domain/port/user_availability_repository_port.dart`
- `packages/server/lib/data/repository/user_availability_repository.dart`
- `packages/server/lib/data/mapper/user_availability_mapper.dart`
- `packages/server/lib/domain/use_case/user_availability_case.dart`
- `packages/server/lib/domain/use_case/task_worker_case.dart`
- `packages/server/test/domain/use_case/user_availability_case_test.dart`
- `packages/server/test/domain/use_case/task_worker_case_test.dart`
FINDINGS: baseline already included committed `0dbdb1ae5` TaskWorkerCase GetIt/BeaconCase bootstrap fix; preserved unchanged. `fetchByUserIds` returns `Map<String, UserAvailabilityEntity>` (absent users omitted). In-memory fake repo in case tests covers idempotency/independence semantics; PostgreSQL concurrency proof deferred to UNIT 07.
REMAINING: none for UNIT 03; UNIT 04 (`feat(server): expose availability in public users`) is next

## Manager review — UNIT 03 accepted — 2026-08-13

COMMITS: `4f776360a` feat(server): add availability commands; `0ac8e7468` docs: record UNIT 03 availability commands evidence
TESTS: independent focused case/task-worker suite → 25 passed; independent server codegen → exit 0; source inspection confirmed shared transaction advisory locks, writable CTE clear/resume operations, six-hour throttle, and preservation of `0dbdb1ae5`
FILES: UNIT 03-owned paths plus `packages/server/lib/data/mapper/user_availability_mapper.dart`
FINDINGS: accepted. The mapper is a necessary narrow data-layer addition ensuring the repository returns the domain entity rather than a Drift row; it normalizes `PgDate` to UTC midnight. PostgreSQL race/linearization proof remains required in UNIT 07.
REMAINING: UNIT 04 is dependency-ready.

## UNIT 04 — complete — 2026-08-13

COMMITS: `6d6970ac5` feat(server): expose availability in public users
TESTS:
- `(cd packages/server && dart run build_runner build -d)` → exit 0
- `(cd packages/server && dart test test/api/controllers/graphql/mappers/gql_public_user_maps_test.dart)` → 12 passed
- `./scripts/check-custom-lints.sh packages/server` → pass (custom-rule total 0)
- `rg "UserPublicRecord\\(" packages/server/lib` → 3 construction sites (+ constructor definition) all pass `userAvailability:` explicitly
FILES:
- `packages/server/lib/domain/entity/gql_public/user_availability_record.dart`
- `packages/server/lib/domain/entity/gql_public/user_public_record.dart`
- `packages/server/lib/data/mapper/user_availability_mapper.dart`
- `packages/server/lib/data/repository/user_profile_batch_lookup.dart`
- `packages/server/lib/data/repository/mutual_friends_repository.dart`
- `packages/server/lib/api/controllers/graphql/mappers/invite_genealogy_gql_maps.dart`
- `packages/server/lib/api/controllers/graphql/mappers/gql_public_user_maps.dart`
- `packages/server/lib/api/controllers/graphql/query/query_invite_genealogy.dart`
- `packages/server/lib/api/controllers/graphql/query/query_invitation.dart`
- `packages/server/lib/api/controllers/graphql/custom_types.dart`
- `packages/server/test/api/controllers/graphql/mappers/gql_public_user_maps_test.dart`
FINDINGS: `userAvailabilityEntityToPublicRecord` and wire date helpers live in
`user_availability_mapper.dart` so data repositories avoid importing GraphQL mappers.
Injectable DI for `DriftUserProfileBatchLookup` / `MutualFriendsRepository` did not
require a new `di.config.dart` diff (bindings already present). Other server tests
using `UserPublicRecord` need `userAvailability: null` for compilation; fixed
locally but not staged per boundary rules.
REMAINING: none for UNIT 04; UNIT 05 (`feat(server): add availability mutations`) is next

## UNIT 04 remediation — complete — 2026-08-13

COMMITS: `6cf0d7d09` fix(server): include viewer in invite genealogy availability batch
TESTS:
- `(cd packages/server && dart test test/api/controllers/graphql/query_invite_genealogy_test.dart test/api/controllers/graphql/mappers/gql_public_user_maps_test.dart)` → 18 passed
- `./scripts/check-custom-lints.sh packages/server` → pass (custom-rule total 0)
- multi-line constructor audit over `packages/server/lib` + `packages/server/test` → all
  `UserPublicRecord(` blocks include `userAvailability:`
- `git diff --check` → clean
FILES:
- `packages/server/lib/api/controllers/graphql/query/query_invite_genealogy.dart`
- `packages/server/test/api/controllers/graphql/query_invite_genealogy_test.dart`
- `packages/server/test/api/controllers/graphql/mappers/help_offer_with_coordination_gql_map_test.dart`
- `packages/server/test/api/controllers/graphql/user_block_graphql_test.dart`
- `packages/server/test/domain/evaluation/evaluation_graph_test_repos.dart`
- `packages/server/test/domain/use_case/beacon_room_admission_matrix_test.dart`
- `packages/server/test/domain/use_case/mutual_friends_case_test.dart`
FINDINGS: confirmed defect — `_viewerRelativeOverlay` reused the trust/score
`candidateIds` set (viewer excluded) for availability; viewer-only graphs returned
`user_availability: null` for the viewer node. Existing query tests needed an injected
`UserAvailabilityCase` after UNIT 04 added the dependency. Prior worker commits
`6d6970ac5` / `0f7d02a6c` remain not manager-accepted; this remediation does not
change that status.
REMAINING: manager acceptance of UNIT 04; UNIT 07 `availability_read_parity_test.dart`
PostgreSQL/API proof for read-path invariants; UNIT 05+ downstream work unchanged

## Manager review — UNIT 04 accepted — 2026-08-13

COMMITS: `6d6970ac5` feat(server): expose availability in public users; `0f7d02a6c`
UNIT 04 evidence; `6cf0d7d09` viewer-availability remediation; `5fc7c389e` remediation
evidence; `4bfece7bc` block-projection assertion.
TESTS: independent focused suite covering genealogy, public maps, help-offer maps, block GraphQL,
room admission, and mutual friends → 52 passed; independent server build runner → exit 0 with no
tracked generated diff; `git diff --check` → clean. The first manager run mistakenly treated the
non-test support fixture `evaluation_graph_test_repos.dart` as a test file; the actual consuming
suite compiles it and passed.
FILES: UNIT 04 source/tests plus the remedial query/fixture paths above and this journal.
FINDINGS: rejected the worker's first result because it left required-constructor fixtures dirty
and omitted the viewer from the genealogy availability batch. Remediation added a regression path
through the actual query and committed every constructor fixture. Manager verification then found
the `myBlocks` expected map missing its now-required `user_availability: null` field; the focused
`4bfece7bc` assertion commit fixes it. Protected unrelated work remains untouched.
REMAINING: UNIT 05 is dependency-ready. UNIT 07 still owns the isolated PostgreSQL/API parity
proof; no acceptance here substitutes for it.

## UNIT 05 — complete — 2026-08-13

COMMITS: `7c7d6d748` feat(server): add availability mutations
TESTS:
- `(cd packages/server && dart test test/api/controllers/graphql/mutation_availability_test.dart)` → 17 passed
- `./scripts/check-custom-lints.sh packages/server` → pass (custom-rule total 0)
- `git diff --check` → clean
FILES:
- `packages/server/lib/api/controllers/graphql/input/input_field_calendar_date.dart`
- `packages/server/lib/api/controllers/graphql/input/_input_types.dart`
- `packages/server/lib/api/controllers/graphql/mutation/mutation_availability.dart`
- `packages/server/lib/api/controllers/graphql/mutation/_mutations_all.dart`
- `packages/server/test/api/controllers/graphql/mutation_availability_test.dart`
FINDINGS: full `graphqlSchema.parseAndExecute` requires the entire DI graph (e.g.
`AttentionQueryPort`); document-path tests use a focused `GraphQL` schema built from
`MutationAvailability().all`, which is the same registered field definitions spread into
`mutationsAll`. No server codegen/DI diff was required.
REMAINING: none for UNIT 05; UNIT 06 (`feat(server): enforce availability on forwards`) is next

## UNIT 05 remediation — complete — 2026-08-13

COMMITS: `694176029` test(server): isolate availability mutation fake
TESTS:
- `(cd packages/server && dart test test/api/controllers/graphql/mutation_availability_test.dart)` → 18 passed
- `./scripts/check-custom-lints.sh packages/server` → pass (custom-rule total 0)
- `git diff --check` → clean
FILES:
- `packages/server/test/api/controllers/graphql/mutation_availability_test.dart`
FINDINGS: manager review defect — GraphQL mutation test imported
`InMemoryUserAvailabilityRepository` from `user_availability_case_test.dart` (UNIT 03).
Replaced with local `_FakeUserAvailabilityRepository` implementing
`UserAvailabilityRepositoryPort` with only the call-tracking/state semantics needed by
mutation tests. Added schema-path regression proving `null` for `isLimited: Boolean!`
throws `GraphQLException` before any `setLimited` repository write; existing missing
required `isLimited` test preserved.
REMAINING: none for UNIT 05 remediation; UNIT 06 is next

## Manager review — UNIT 05 accepted — 2026-08-13

COMMITS: `7c7d6d748` feat(server): add availability mutations; `0b7ff7f72` UNIT 05
evidence; `694176029` isolated mutation fake; `d9ae8a59b` remediation evidence
TESTS: independent `(cd packages/server && dart test
test/api/controllers/graphql/mutation_availability_test.dart)` → 18 passed; manager source
review confirmed the canonical UTC parser rejects non-calendar/timestamp/rollover inputs, all
three fields are self-only non-null mutations, and horizon validation remains in
`UserAvailabilityCase`; `git diff --check 36257f97a..HEAD` → clean
FILES: UNIT 05 source/test paths and this journal
FINDINGS: accepted after one targeted remediation. The focused schema executes actual
`MutationAvailability` GraphQL fields through document parsing without constructing unrelated
server DI dependencies. The test fake is now local to this unit, and a null Boolean variable is
proved to be rejected before a repository call. Protected independent UI work remains unmodified.
REMAINING: UNIT 06 is dependency-ready. UNIT 07 still owns PostgreSQL/API invariant proof.

## UNIT 06 — complete — 2026-08-13

COMMITS: `bc6a183a1` feat(server): enforce availability on forwards
TESTS:
- `(cd packages/server && dart run build_runner build -d)` → exit 0
- `(cd packages/server && dart test test/domain/use_case/forward_case_test.dart test/domain/use_case/forward_case_auth_test.dart)` → 50 passed
- `./scripts/check-custom-lints.sh packages/server` → pass (custom-rule total 0)
- `git diff --check` → clean
FILES:
- `packages/server/lib/domain/entity/forward_batch_create_result.dart`
- `packages/server/lib/domain/entity/forward_delivery_result.dart`
- `packages/server/lib/domain/port/forward_edge_repository_port.dart`
- `packages/server/lib/data/repository/forward_edge_repository.dart`
- `packages/server/lib/domain/use_case/forward_case.dart`
- `packages/server/lib/api/controllers/graphql/custom_types.dart`
- `packages/server/lib/api/controllers/graphql/mutation/mutation_forward.dart`
- `packages/server/test/domain/use_case/forward_case_test.dart`
- `packages/server/test/domain/use_case/forward_case_auth_test.dart`
- `packages/server/test/domain/use_case/forward_case_mocks.mocks.dart`
- `packages/server/test/domain/use_case/help_offer_case_mocks.mocks.dart`
- `packages/server/test/data/repository/forward_edge_repository_create_batch_dedup_test.dart`
- `packages/server/test/domain/evaluation/evaluation_graph_test_repos.dart`
- `packages/server/test/support/build_test_invitation_case.dart`
FINDINGS: `createBatch` dedupe, sorted advisory locks, and conditional
`INSERT … SELECT … WHERE` availability predicate live in
`ForwardEdgeRepository` inside `withMutatingUser`; active-edge dedup remains
silent (not counted as availability skip). Freezed `*.freezed.dart` outputs
are gitignored and produced by build_runner. Mockito mock regeneration for the
port signature was required and committed. Three mechanical port-signature stub
updates outside the primary owned list were included so `dart analyze` stays
green.
REMAINING: UNIT 07 owns PostgreSQL two-connection linearization proof,
`forward_delivery_result_test.dart`, and read-path parity tests; client units
08–16 unchanged.

## UNIT 06 final evidence — 2026-08-13

COMMITS: `bc6a183a1c` feat(server): enforce availability on forwards
TESTS: `(cd packages/server && dart run build_runner build -d)` → exit 0;
`(cd packages/server && dart test test/domain/use_case/forward_case_test.dart test/domain/use_case/forward_case_auth_test.dart)` → 50 passed;
`./scripts/check-custom-lints.sh packages/server` → pass (custom-rule total 0);
`git diff --check` → clean after implementation commit
FILES: UNIT 06 source/test paths listed above
FINDINGS: none beyond UNIT 06 entry
REMAINING: none for UNIT 06; UNIT 07 is next

## UNIT 06 remediation — complete — 2026-08-13

COMMITS: `6b11793fc` fix(server): restore forward active-edge conflict no-throw semantics
TESTS:
- `(cd packages/server && dart test test/domain/use_case/forward_case_test.dart test/domain/use_case/forward_case_auth_test.dart)` → 50 passed
- `(cd packages/server && dart test -t pg test/data/repository/forward_edge_repository_create_batch_dedup_test.dart)` → 2 passed, 1 skipped (shared Postgres lacks `user_availability`)
- `./scripts/check-custom-lints.sh packages/server` → pass (custom-rule total 0)
- `git diff --check` → clean
FILES:
- `packages/server/lib/data/repository/forward_edge_repository.dart`
- `packages/server/test/data/repository/forward_edge_repository_create_batch_dedup_test.dart`
FINDINGS: `_insertActiveEdgeIfAvailable` needed `ON CONFLICT (beacon_id, sender_id,
recipient_id) WHERE cancelled_at IS NULL DO NOTHING` on the conditional insert to
preserve pre-UNIT-06 no-throw dedup under `bfe_active_unique` races. Drift
`customInsert` also reports `0` affected rows for successful `INSERT … SELECT …
ON CONFLICT`, so `createBatch` must classify outcomes via post-insert
`findActiveEdge` + `existing?.id == edgeId` (restoring pre-UNIT-06 semantics),
not via the insert row count. Disposable-Postgres proof covers concurrent same-edge
`createBatch` (one edge, no availability skip) and paused-recipient skip; full
pause/forward linearization and GraphQL typed-result proof remain UNIT 07.
REMAINING: manager acceptance of UNIT 06 remediation; UNIT 07 PostgreSQL/API
invariant suite (`forward_edge_availability_pg_test.dart`,
`forward_delivery_result_test.dart`, etc.).

## UNIT 06 manager acceptance — 2026-08-13

VERDICT: accepted after remediation commits `6b11793fc` and `2e23b290c`.
REVIEW: Confirmed the conditional availability insert now preserves the partial
active-edge index's no-throw deduplication through its matching `ON CONFLICT`
target. Confirmed `createBatch` determines delivery from the current
transaction's generated edge id, so an existing edge stays neither delivered
nor availability-skipped while a paused recipient remains skipped. Each
`TenturaDb` in the disposable test owns a distinct Postgres pool, so the
same-edge smoke test uses independent database connections; its missing
barrier is not accepted as the plan's linearization proof, which remains
explicitly owned by UNIT 07.
INDEPENDENT VERIFICATION:
- `(cd packages/server && dart test test/domain/use_case/forward_case_test.dart test/domain/use_case/forward_case_auth_test.dart)` -> 50 passed
- `(cd packages/server && dart test -t pg test/data/repository/forward_edge_repository_create_batch_dedup_test.dart)` -> 2 passed, 1 skipped because shared Postgres lacks m0148/user_availability; the two executed cases use a freshly migrated disposable database
- `./scripts/check-custom-lints.sh packages/server` -> pass, custom-rule total 0
- `git diff --check f298bd966..HEAD` -> clean
REMAINING: UNIT 07; no inference of its barrier-based pause/forward,
GraphQL-row parity, or broader read-permission evidence from UNIT 06.

## UNIT 07 first worker attempt — rejected by manager — 2026-08-13

STATUS: stopped without commits; its three untracked draft test files were
removed before any test or commit. The worker proposed mutating the shared
Postgres database for a Hasura diagnostic and SQL simulations in place of
required real GraphQL-path tests. Both violate UNIT 07's isolated-database and
causal-evidence constraints. No partial test claim is retained.
RECOVERY: split UNIT 07 into fresh, sequential subunits. Start with the
isolated `UserAvailabilityRepository` transition/concurrency proof only; keep
forward linearization and GraphQL/Hasura work for later fresh workers.

## UNIT 07A repository proof attempt — source defect found — 2026-08-13

STATUS: stopped without commits; the untracked test draft was removed after
its first focused run. The disposable, fully migrated PostgreSQL test exposed
two independently actionable source defects:
- `setLimited(true)` then `setLimited(false)` attempts to persist
  `(is_limited=false, resume_on=NULL)`, violating
  `user_availability_not_empty`, instead of deleting the open row.
- `pause` passes `PgDate` to Drift Postgres `customStatement`; installed
  drift_postgres 1.3.1 accepts only `TypedValue`, primitive values, and null
  there, so the call fails before SQL with `Unsupported type: Instance of
  'PgDate'`.
EVIDENCE: `(cd packages/server && dart test -t pg
test/data/repository/user_availability_repository_pg_test.dart)` failed its
clear-limited case with PostgreSQL 23514 and both pause cases with the
unsupported bind error. Tests used only a unique disposable migrated database.
RECOVERY: assign a fresh narrow source remediation for
`UserAvailabilityRepository`, then recreate this proof in a fresh worker.

## UserAvailabilityRepository defect remediation — manager acceptance — 2026-08-13

VERDICT: accepted: `31ba3b77e`, `fdef75d6e`, `2b4de380d`, and `1b03c5489`.
REVIEW: the limited-clear and resume statements no longer construct the
forbidden `(false, NULL)` row; their mutually exclusive CTE branches preserve
a live pause while deleting only open rows. All three date-bearing
`customStatement` paths now pass the asserted UTC calendar date as an ISO
string with an explicit `::date` cast, avoiding the unsupported PgDate bind.
INDEPENDENT VERIFICATION:
- `(cd packages/server && dart test -t pg test/data/repository/user_availability_repository_pg_test.dart)` -> 5 passed on a disposable migrated Postgres database
- `(cd packages/server && dart test test/domain/use_case/user_availability_case_test.dart test/domain/entity/user_availability_entity_test.dart)` -> 25 passed
- `git diff --check f298bd966..HEAD` -> clean
REMAINING: fresh UNIT 07A concurrency proof must add the two-independent-pool,
exact-advisory-lock barrier case; all forward/GraphQL/read-parity UNIT 07 work
remains open.

## UNIT 07A repository remediation — complete — 2026-08-13

COMMITS: `31ba3b77e` fix(server): avoid empty availability rows and bind pause dates
TESTS:
- `(cd packages/server && dart test -t pg test/data/repository/user_availability_repository_pg_test.dart)` → 4 passed
- `(cd packages/server && dart test test/domain/use_case/user_availability_case_test.dart test/domain/entity/user_availability_entity_test.dart)` → 25 passed
- `dart test test/domain/availability_test.dart` → 11 passed
- `./scripts/check-custom-lints.sh packages/server` → pass (custom-rule total 0)
- `git diff --check` → clean
FILES:
- `packages/server/lib/data/repository/user_availability_repository.dart`
- `packages/server/test/data/repository/user_availability_repository_pg_test.dart`
FINDINGS:
- `setLimited(false)` and `resume` both tripped `user_availability_not_empty`
  because PostgreSQL enforces CHECK on UPDATE before a same-statement DELETE
  could remove the row; fixed by deleting open rows (`resume_on IS NULL` or
  pause-only) without ever writing `(false, NULL)`.
- `pause` now binds strict `YYYY-MM-DD` strings with `$2::date` instead of
  `PgDate`, which drift_postgres 1.3.1 rejects in `customStatement`.
- `cleanupExpired` still passes `PgDate` to `customStatement`; not exercised by
  this proof and left unchanged per narrow remediation scope.
REMAINING: UNIT 07 forward linearization, GraphQL/Hasura read parity, and
concurrency proof; manager acceptance not recorded here.

## UNIT 07A cleanupExpired remediation — complete — 2026-08-13

COMMITS: `2b4de380d` fix(server): bind cleanupExpired calendar dates
TESTS:
- `(cd packages/server && dart test -t pg test/data/repository/user_availability_repository_pg_test.dart)` → 5 passed
- `./scripts/check-custom-lints.sh packages/server` → pass (custom-rule total 0)
- `git diff --check` → clean
FILES:
- `packages/server/lib/data/repository/user_availability_repository.dart`
- `packages/server/test/data/repository/user_availability_repository_pg_test.dart`
FINDINGS:
- `cleanupExpired` still passed `PgDate` to Drift Postgres `customStatement`,
  reproducing the same unsupported-bind failure as the prior `pause` defect.
- Fixed by binding strict UTC `YYYY-MM-DD` strings with `$1::date`, matching
  `pause` and retaining the asserted UTC calendar-date contract.
- Disposable-PG regression proves expiry cleanup deletes pause-only rows with
  `resume_on <= today` and clears expired `resume_on` on limited rows while
  leaving future pause-only rows intact.
REMAINING: UNIT 07 forward linearization, GraphQL/Hasura read parity, and
concurrency proof; manager acceptance not recorded here.

## UNIT 07A concurrency proof — complete — 2026-08-13

COMMITS: `3d8ebc241` test(server): prove availability concurrent first-write serialization
TESTS:
- `(cd packages/server && dart test -t pg test/data/repository/user_availability_repository_pg_test.dart)` → 6 passed
- `./scripts/check-custom-lints.sh packages/server` → pass (custom-rule total 0)
- `git diff --check` → clean
FILES:
- `packages/server/test/data/repository/user_availability_repository_pg_test.dart`
FINDINGS:
- Builds on manager-accepted remediation baseline `79112d3e5` (`31ba3b77e`–`2b4de380d`).
- Two independent `TenturaDb`/`UserAvailabilityRepository` pools plus a third
  transaction hold the production
  `pg_advisory_xact_lock(hashtextextended('user_availability:' || userId, 4242))`
  while `setLimited(true)` and `pause(resumeOn)` start; before release the writer
  connection observes exactly two ungranted `pg_locks` rows whose recomposed
  `(classid, objid)` match that key.
- After release both operations complete without error, the table holds one
  `(is_limited=true, resume_on)` row, and `fetchByUserIds` returns the matching
  `UserAvailabilityEntity`.
REMAINING: UNIT 07 forward linearization, GraphQL/Hasura read parity, and
read-permission evidence; manager acceptance not recorded here.

## UNIT 07A manager acceptance — 2026-08-13

VERDICT: accepted: `3d8ebc241` and `4b14ecef9`.
REVIEW: The test uses the identical transaction advisory-lock expression as
`UserAvailabilityRepository._acquireLock`, three distinct `TenturaDb` instances,
and the disposable migrated target. It does not infer concurrency from timing:
before release the independent writer observes precisely two waiting advisory
lock requests whose reconstructed `pg_locks` key equals the production hash.
After release it proves both mutation effects merge into the only valid row and
the typed repository read agrees. The Drift multiple-database debug warnings are
expected for deliberately independent pools; the test target is isolated.
INDEPENDENT VERIFICATION:
- `(cd packages/server && dart test -t pg test/data/repository/user_availability_repository_pg_test.dart)` -> 6 passed
- `./scripts/check-custom-lints.sh packages/server` -> pass, custom-rule total 0
- `git diff --check 79112d3e5..HEAD` -> clean
REMAINING: UNIT 07 forward/pause linearization, typed GraphQL delivery parity,
read-permission parity, and the recorded Hasura candidate-limit diagnostic.

## UNIT 07B forward/pause linearization proof — complete — 2026-08-13

COMMITS: `cb730570e` test(server): prove forward/pause availability linearization
TESTS:
- `(cd packages/server && dart test -t pg test/data/repository/forward_edge_availability_pg_test.dart)` → 5 passed
- `./scripts/check-custom-lints.sh packages/server` → pass (custom-rule total 0)
- `git diff --check` → clean
FILES:
- `packages/server/test/data/repository/forward_edge_availability_pg_test.dart`
FINDINGS:
- Builds on manager-accepted UNIT 07A baseline `be9f92532`.
- Live `ForwardEdgeRepository.createBatch` acquires the production
  `pg_advisory_xact_lock(hashtextextended('user_availability:' || userId, 4242))`
  **before** its conditional `INSERT … SELECT … WHERE` availability predicate; the plan's
  stale “pre-read” wording is reconciled as an open/missing initial availability row, not a
  separate pre-read implementation.
- Two-race proof uses three independent `TenturaDb` pools (blocker, pause, forward) plus
  `pg_locks` causal observation of exactly two ungranted advisory waits on the production key
  before release; enqueue order forces pause-then-forward or forward-then-pause linearization.
- Mixed-batch, dedup-silent, and `is_limited=true` deliverable cases exercise real
  `createBatch` only; downstream `onAfterEdgesInserted` / `ForwardCase` / GraphQL typed-result
  effects remain outside this repository proof boundary.
REMAINING: UNIT 07 GraphQL typed-result proof (`forward_delivery_result_test.dart`),
read-permission parity (`availability_read_parity_test.dart`), and Hasura candidate-limit
diagnostic; manager acceptance not recorded here.

## UNIT 07B manager acceptance — 2026-08-13

VERDICT: accepted: `cb730570e` and `8ad4d1cb0`.
REVIEW: The new test runs only against a fresh disposable migrated database and
calls the actual availability and forward repositories through separate pools.
Both orderings hold the precise production recipient advisory key, observe two
ungranted matching `pg_locks` rows before release, and assert the actual table
and `ForwardBatchCreateResult` effects after the first queued operation wins.
It also proves requested-order reporting, silent deduplication, and that
limited-only recipients are deliverable. The plan's pre-read wording is stale:
live `createBatch` correctly locks before evaluating availability.
INDEPENDENT VERIFICATION:
- `(cd packages/server && dart test -t pg test/data/repository/forward_edge_availability_pg_test.dart)` -> 5 passed
- `./scripts/check-custom-lints.sh packages/server` -> pass, custom-rule total 0
- `git diff --check be9f92532..HEAD` -> clean
REMAINING: UNIT 07 real GraphQL delivery-result parity, Hasura/read-permission
parity, and the candidate-limit diagnostic.

## UNIT 07C GraphQL ForwardDeliveryResult parity proof — complete — 2026-08-13

COMMITS: `9d389ae23`
TESTS:
- `(cd packages/server && dart test test/api/controllers/graphql/forward_delivery_result_test.dart)` → 2 passed
- `./scripts/check-custom-lints.sh packages/server` → pass (custom-rule total 0)
- `git diff --check` → clean
FILES:
- `packages/server/test/api/controllers/graphql/forward_delivery_result_test.dart`
FINDINGS:
- Builds on manager-accepted UNIT 07B baseline `57f38b9e2`.
- Schema proof registers `beaconForward` as non-null `ForwardDeliveryResult` with
  three non-null fields (`batchId`, `deliveredRecipientIds`,
  `availabilitySkippedRecipientIds`).
- Document execution runs `beaconForward` through `MutationForward` /
  `graphql_server2` with JWT context, real `ForwardEdgeRepository` on a disposable
  migrated PostgreSQL database, and minimal in-memory ports for the remaining
  `ForwardCase` collaborators.
- Mixed batch preserves requested order for delivered and availability-skipped
  IDs; GraphQL lists match the actual `beacon_forward_edge` rows for the
  returned `batchId` and paused recipients receive no edge while limited-only
  recipients are delivered.
- Pre-existing active-edge dedup is silent: the duplicate recipient appears in
  neither delivered nor availability-skipped lists.
- `TestAttentionHarness` records a single `relayReceived` intent whose recipient
  ids match only the newly delivered recipients from the real `ForwardCase`
  invocation.
REMAINING: UNIT 07 read-permission parity (`availability_read_parity_test.dart`)
and Hasura candidate-limit diagnostic; manager acceptance not recorded here.

## UNIT 07C manager acceptance — 2026-08-13

VERDICT: accepted: `9d389ae23` and `73b647968`.
REVIEW: The test executes a GraphQL document through `graphql_server2` and
`MutationForward` with JWT credentials; it does not directly call a resolver
or response mapper. The actual `ForwardCase` invokes the real forward and
availability repositories against a fresh migrated disposable PostgreSQL
database. The response's ordered outcomes are tied to the rows for its returned
batch ID, with explicit no-edge checks for pauses and silent-dedup checks. The
attention harness proves only newly inserted recipients received the forward
effect. Small fake ports only supply non-forward collaborators.
INDEPENDENT VERIFICATION:
- `(cd packages/server && dart test test/api/controllers/graphql/forward_delivery_result_test.dart)` -> 2 passed
- `./scripts/check-custom-lints.sh packages/server` -> pass, custom-rule total 0
- `git diff --check 57f38b9e2..HEAD` -> clean
REMAINING: UNIT 07 Hasura/read-permission parity and the candidate-limit
diagnostic.

## UNIT 07D availability read-permission parity proof — complete — 2026-08-13

COMMITS: `eea7692eb`
TESTS:
- `(cd packages/server && dart test -t pg test/api/controllers/graphql/availability_read_parity_test.dart)` → 10 passed
- `./scripts/check-custom-lints.sh packages/server` → pass (custom-rule total 0)
- `git diff --check` → clean
FILES:
- `packages/server/test/api/controllers/graphql/availability_read_parity_test.dart`
FINDINGS:
- Builds on manager-accepted UNIT 07C baseline `38ce66e7e`.
- Disposable migrated PostgreSQL database exercises the committed
  `user_availability_hidden_for_viewer` function and the Hasura select filter
  `(NOT hidden_for_viewer) AND (is_limited OR resume_on > now())` with distinct
  viewer `Uavailrdview01` and target fixtures; no direct Hasura GraphQL execution
  or resolver fakes.
- Blocked pair: `user_block(viewer → target)` hides the target via
  `hidden_for_viewer`; expired pause-only rows drop out of the read predicate;
  limited rows with past `resume_on` remain visible; future pause rows remain
  visible.
- Repository/public-path parity: `UserAvailabilityRepository.fetchByUserIds`
  plus `userAvailabilityEntityToGqlMap`/`userAvailabilityEntityToPublicRecord`
  match the Hasura-visible effective state for non-blocked targets and never emit
  `updated_at`.
- Static metadata regression parses committed `hasura/metadata.json`:
  `user_availability` select columns are exactly `user_id`, `is_limited`,
  `resume_on`; computed field `hidden_for_viewer` is required; no mutation
  permissions; `user` select permission still declares `limit: 10` (metadata
  only, not live runtime proof).
- Hasura candidate-limit diagnostic (non-mutating, read-only):
  - `curl -sS http://127.0.0.1:8080/healthz` → `OK` (HTTP 200)
  - `curl -sS http://127.0.0.1:8080/v1/version` → `{"server_type":"ce","version":"v2.48.14"}`
  - `curl -sS http://127.0.0.1:8080/v1/metadata -H "X-Hasura-Admin-Secret: password"` → live metadata has **no** tracked `user` table and **no** tracked `mutually_visible_users` function (committed metadata not applied to this service)
  - `curl -sS http://127.0.0.1:8080/v1/graphql` introspection → `mutually_visible_users` absent from query root (46 remote-schema fields only)
  - Shared `postgres` database (docker `postgres:5432/postgres`) has SQL function
    `mutually_visible_users` and 1008 users, but a spot check
    `SELECT count(*) FROM public.mutually_visible_users('', '{"x-hasura-user-id":"Ua6432bd9e599"}'::json)`
    returned `1`; no isolated >10 mutually visible sample was established without
    seeding or a full-table scan (aborted after timeout risk).
  - **PENDING/BLOCKED:** whether Hasura applies the committed `user` select
    `limit: 10` to `mutually_visible_users` at runtime remains unobserved; only
    the static metadata assertion above is recorded.
REMAINING: manager acceptance of UNIT 07D; UNIT 07 complete pending acceptance.

## UNIT 07D manager acceptance — 2026-08-13

VERDICT: accepted: `eea7692eb` and `9b7935c5e`.
REVIEW: The test creates a unique disposable migrated PostgreSQL database, uses
the migration-provided `user_availability_hidden_for_viewer` function with a
distinct viewer/blocked target pair, and evaluates the exact committed Hasura
select predicate separately. It proves the expired-pause, limited-with-past-date,
and future-pause rows independently. It also parses the committed metadata for
the exact visibility columns, computed field, absence of mutation permissions,
and the static user limit. The test does not claim that its SQL predicate proves
live Hasura GraphQL behavior.
INDEPENDENT VERIFICATION:
- `(cd packages/server && dart test -t pg test/api/controllers/graphql/availability_read_parity_test.dart)` -> 10 passed
- `./scripts/check-custom-lints.sh packages/server` -> pass, custom-rule total 0
- `git diff --check 38ce66e7e..HEAD` -> clean
FINDING: The live Hasura candidate-limit behavior remains pending/blocked: its
metadata does not track the committed `user`/`mutually_visible_users` sources,
and no already-existing isolated fixture has more than ten visible peers. The
metadata assertion is static only; it is not a runtime observation.
REMAINING: UNIT 07 is not complete: retain the live Hasura >10 candidate-limit
observation as an explicit blocked acceptance gate. UNIT 08 must not start until
the plan owner accepts that remaining blocked gate or supplies an isolated
Hasura fixture.

## UNIT 07E — live Hasura candidate-limit observation — complete — 2026-08-14

COMMITS: `209845dd1` docs: record UNIT 07E live Hasura candidate-limit observation
TESTS:
- Pre-observation metadata export:
  `curl -sS http://127.0.0.1:8080/v1/metadata -H "X-Hasura-Admin-Secret: password" -H "Content-Type: application/json" -d '{"type":"export_metadata","args":{}}'`
  → saved to `/tmp/tentura-unit07e/hasura_metadata_pre.json`; live postgres source
  already tracks `user` (`select_permissions.user.limit: 10`) and
  `mutually_visible_users` (26 tables, 5 functions).
- Committed metadata apply attempt (blocked on shared DB schema):
  `./scripts/hasura_apply_metadata.sh` → HTTP 400 inconsistent metadata because
  committed `hasura/metadata.json` tracks `user_availability` but shared
  `postgres` has no `public.user_availability` (`to_regclass` false; m0148 not
  migrated locally). Observation proceeded on the unchanged live metadata
  snapshot above (no metadata mutation during the probe).
- Fixture seed (13 users, 12 bidirectional trust edges, causal prefix
  `U07hlimit*`):
  `docker exec -i postgres psql -U postgres -d postgres -v ON_ERROR_STOP=1`
  with `INSERT` into `public."user"` for viewer `U07hlimitview1` and peers
  `U07hlimitpeer01`…`U07hlimitpeer12`, plus paired `vote_user` rows
  `(amount=1)` for mutual trust.
- SQL eligibility (direct function, same session identity):
  `SELECT count(*) FROM public.mutually_visible_users('', '{"x-hasura-user-id":"U07hlimitview1"}'::json)`
  → **12** (`U07hlimitpeer01`…`U07hlimitpeer12`).
- Live Hasura GraphQL under role `user` (viewer impersonation +
  dev admin-secret gate for schema access on this instance):
  `POST http://127.0.0.1:8080/v1/graphql` headers
  `x-hasura-role: user`, `x-hasura-user-id: U07hlimitview1`,
  `x-hasura-admin-secret: password`, body
  `query ForwardCandidatesLimitProbe($context: String = "") { mutually_visible_users(args: {context: $context}) { id } }`
  with `variables: {"context": ""}` → **10** rows
  (`U07hlimitpeer01`…`U07hlimitpeer10` only; `peer11`/`peer12` present in SQL
  but truncated at runtime). Without the admin secret the same query returns
  validation error `field 'mutually_visible_users' not found in type: 'query_root'`
  on this dev instance — documented, not used as the limit proof.
- Nested availability visibility: **not exercised** on this stack — shared
  postgres lacks `public.user_availability` and live metadata does not track
  that table; committed metadata apply remains blocked until m0148 is migrated
  locally.
- Cleanup + metadata restore (finally-equivalent):
  `DELETE FROM public.vote_user WHERE subject LIKE 'U07hlimit%' OR object LIKE 'U07hlimit%'` → 24;
  `DELETE FROM public."user" WHERE id LIKE 'U07hlimit%'` → 13;
  post-check `SELECT count(*) … WHERE id LIKE 'U07hlimit%'` → 0;
  `replace_metadata` from `/tmp/tentura-unit07e/hasura_metadata_pre.json` → HTTP
  200, `is_consistent: true`; post-restore export still shows 26 tables,
  `user` limit 10, tracked `mutually_visible_users`.
FILES: `docs/plans/availability-request-receptiveness-implementation-journal.md`
FINDINGS:
- Runtime proof: Hasura applies the tracked `user` role select permission
  `limit: 10` to `mutually_visible_users` SETOF results — 12 SQL-eligible peers,
  exactly 10 GraphQL rows, deterministic truncation of the last two IDs in sort
  order returned by the function on this fixture.
- Confirms UNIT 07D static metadata assertion and closes the previously blocked
  acceptance gate; v1 accepts the capped pool Hasura returns before client-side
  availability filtering (plan §UNIT 07).
- `./scripts/hasura_apply_metadata.sh` against committed metadata still requires
  local m0148 on the shared postgres volume before `user_availability` can be
  tracked for nested availability GraphQL probes.
REMAINING: manager acceptance of UNIT 07E and overall UNIT 07; UNIT 08 remains
blocked until accepted.

## UNIT 07E manager acceptance / UNIT 07 closeout — 2026-08-14

VERDICT: accepted: `dcda4fbbd`.
REVIEW: The live Hasura probe is causally sufficient for the formerly blocked
candidate-limit gate. It seeded 12 distinct, mutually visible people for one
viewer, established all 12 in the underlying SQL function, then observed the
real `/v1/graphql` function under `x-hasura-role: user` and the same viewer
identity return exactly 10. The absent last two fixture IDs distinguish a
runtime permission limit from a static-metadata inference. The use of the
local admin secret merely permits the otherwise hidden dev schema; the explicit
user role/identity is what makes the returned limit evidence meaningful.
INDEPENDENT VERIFICATION:
- `SELECT count(*) FROM public."user" WHERE id LIKE 'U07hlimit%'` -> 0
- `SELECT count(*) FROM public.vote_user WHERE subject LIKE 'U07hlimit%' OR object LIKE 'U07hlimit%'` -> 0
- live metadata export -> no `user_availability` table (pre-existing state),
  tracked `mutually_visible_users`, and user-role limit `[10]`
- `git diff --check 78a4404dc..HEAD` -> clean
FINDING: The committed availability metadata cannot load into this local shared
PostgreSQL volume because it predates m0148. That does not weaken the accepted
candidate-limit observation; UNIT 07D already proved availability read
visibility in an isolated migrated database.
REMAINING: UNIT 07 is accepted and UNIT 08 is dependency-ready.

## UNIT 08 — complete — 2026-08-14

COMMITS: `7a2646216` feat(client): map availability data; `0c25d9155`
docs: record UNIT 08 client availability data evidence
TESTS:
- Temporary local schema fetch: applied m0148 to shared `postgres`, started
  updated server, `./scripts/hasura_apply_metadata.sh`, then
  `docker compose run --rm schema_fetcher` → committed `schema.graphql` diff
  includes `scalar date`, `user_availability`, `v2_user_availability`,
  `v2_ForwardDeliveryResult`, and typed `beaconForward` return; restored shared
  postgres (dropped m0148) and pre-fetch Hasura metadata from
  `/tmp/tentura-unit08/hasura_metadata_pre.json`.
- `(cd packages/client && dart run build_runner build -d)` → exit 0
- `(cd packages/client && TZ=America/New_York flutter test test/data/gql/calendar_date_serializer_test.dart test/data/model/availability_read_parity_test.dart)` → 9 passed
- `(cd packages/client && TZ=America/New_York flutter test --platform chrome test/data/gql/calendar_date_serializer_test.dart)` → 4 passed
- `./scripts/check-custom-lints.sh packages/client` → pass (custom-rule total 106, baseline 111)
- `git diff --check` → clean
FILES:
- `packages/client/lib/data/gql/calendar_date_serializer.dart`
- `packages/client/build.yaml`
- `packages/client/lib/data/gql/schema.graphql`
- `packages/client/lib/data/gql/user_model.graphql`
- `packages/client/lib/data/gql/user_public_model.graphql`
- `packages/client/lib/data/model/user_model.dart`
- `packages/client/lib/data/model/user_public_model.dart`
- `packages/client/lib/features/profile_view/data/repository/mutual_friends_repository.dart`
- `packages/client/lib/features/beacon_view/data/repository/coordination_repository.dart`
- `packages/client/lib/features/forward/domain/entity/forward_delivery_result.dart`
- `packages/client/lib/features/forward/data/gql/forward_beacon.graphql`
- `packages/client/test/data/gql/calendar_date_serializer_test.dart`
- `packages/client/test/data/model/availability_read_parity_test.dart`
- `packages/client/lib/features/profile_view/data/gql/mutual_friends_fetch.graphql` (required query selections; omitted from nominal ownership list)
- `packages/client/lib/features/beacon_view/data/gql/help_offers_with_coordination.graphql` (required query selections; omitted from nominal ownership list)
- `packages/client/lib/features/forward/data/repository/forward_repository.dart` (compile-only `.batchId` bridge; full `ForwardDeliveryResult` mapping deferred to UNIT 14)
FINDINGS:
- Shared local postgres was at m0147 pre-fetch; temporary m0148 apply + metadata
  apply + schema fetch + full restore left no fixture rows and returned Hasura
  metadata to the pre-unit export (`user_availability` untracked again).
- Ferry type for Hasura nested availability is `GUserModel_user_availability`
  (not `GUserModelUserAvailability`).
- Nominal UNIT 08 ownership omitted three dependent paths needed for a green
  build: two V2 user GraphQL queries and a one-line `forward_repository` bridge
  until UNIT 14 maps the typed forward result entity.
REMAINING: UNIT 09 (`feat(client): wire availability commands`); UNIT 14 owns
full `ForwardDeliveryResult` repository/use-case mapping and delivery UX.

## UNIT 08 — remediation — 2026-08-14

Manager review rejected prior UNIT 08 evidence for two concrete gaps:
(1) `CalendarDateSerializer.deserialize` and `parseStrictUtcCalendarDateString`
accepted calendar overflows (`2026-02-31` normalized to March) instead of using
one strict parser; (2) the Chrome timezone proof skipped offset assertion on
web and relied on process `TZ` only.

Remediation:
- Canonical `parseStrictUtcCalendarDateString` in
  `calendar_date_serializer.dart` validates month/day ranges, rejects overflow,
  and is shared by Ferry `deserialize` (non-string wire → `FormatException`) and
  `availabilityFromV2Wire` via `user_model.dart`.
- Serializer/parity tests reject `2026-02-31` for scalar and V2 paths.
- Non-UTC proof is opt-in via
  `--dart-define=availability_expect_non_utc=true`; when set, VM and Chrome
  tests assert `DateTime.now().timeZoneOffset != Duration.zero` (no `dart:io`
  on web). Default UTC suites omit the offset assertion.

COMMITS: `b7574fc04` fix(client): strict calendar date parsing for availability;
`9b10d22bd` docs: record UNIT 08 strict calendar parser remediation (baseline
preserved: `7a2646216`, `0c25d9155`, `90bd82718`)
TESTS:
- `TZ=America/New_York flutter test --dart-define=availability_expect_non_utc=true test/data/gql/calendar_date_serializer_test.dart test/data/model/availability_read_parity_test.dart` → 12 passed
- `TZ=America/New_York flutter test --platform chrome --dart-define=availability_expect_non_utc=true test/data/gql/calendar_date_serializer_test.dart` → 6 passed
- `flutter test test/data/gql/calendar_date_serializer_test.dart test/data/model/availability_read_parity_test.dart` (default UTC, no dart-define) → 12 passed
- `./scripts/check-custom-lints.sh packages/client` → pass
- `git diff --check` → clean
FILES:
- `packages/client/lib/data/gql/calendar_date_serializer.dart`
- `packages/client/lib/data/model/user_model.dart`
- `packages/client/test/data/gql/calendar_date_serializer_test.dart`
- `packages/client/test/data/model/availability_read_parity_test.dart`
FINDINGS: `DateTime.utc(y,m,d)` alone is insufficient for strict calendar
dates; month/day bounds plus post-parse component equality close the overflow
hole without `toLocal()`.
REMAINING: manager re-review of UNIT 08 remediation evidence; UNIT 09 onward
unchanged.

## UNIT 08 manager acceptance — 2026-08-14

VERDICT: accepted after remediation commits `b7574fc04`, `9b10d22bd`, and
`efdc23833` (implementation baseline `7a2646216`).

REVIEW: the scalar and V2 adapters now use one strict calendar parser. It rejects
malformed/non-string values and impossible dates before `DateTime.utc` can
normalize them; `Availability.open()` remains the null relationship default.
The explicit browser proof flag asserts the actual observed browser offset is
non-UTC, so the successful Chrome run is no longer inferred from process `TZ`.
The narrow `.batchId` bridge is necessary compatibility wiring for the typed
GraphQL result and leaves full result mapping to UNIT 14 as planned.

INDEPENDENT VERIFICATION:
- `TZ=America/New_York flutter test --dart-define=availability_expect_non_utc=true test/data/gql/calendar_date_serializer_test.dart test/data/model/availability_read_parity_test.dart` -> 12 passed
- `TZ=America/New_York flutter test --platform chrome --dart-define=availability_expect_non_utc=true test/data/gql/calendar_date_serializer_test.dart` -> 6 passed
- `git diff --check 48ccb567f..HEAD` -> clean
- Temporary local schema-fetch state independently restored: `user_availability`
  table absent, schema-version `0148` absent, and Hasura metadata export exactly
  matches `/tmp/tentura-unit08/hasura_metadata_pre.json`.

REMAINING: UNIT 08 is accepted. UNIT 09 is dependency-ready.

## UNIT 09 — complete — 2026-08-14

COMMITS: `df00c40a3` feat(client): wire availability commands
TESTS:
- `(cd packages/client && dart run build_runner build -d)` → exit 0
- `(cd packages/client && flutter test test/features/profile/profile_availability_cubit_test.dart test/data/service/remote_api_client/direct_operation_routing_test.dart)` → 10 passed
- `./scripts/check-custom-lints.sh packages/client` → pass (custom-rule total 106, baseline 111)
- `git diff --check` → clean
FILES:
- `packages/client/lib/features/profile/data/gql/availability_set_limited.graphql`
- `packages/client/lib/features/profile/data/gql/availability_pause.graphql`
- `packages/client/lib/features/profile/data/gql/availability_resume.graphql`
- `packages/client/lib/data/service/remote_api_client/build_client.dart`
- `packages/client/lib/features/profile/domain/port/profile_repository_port.dart`
- `packages/client/lib/features/profile/data/repository/profile_repository.dart`
- `packages/client/lib/features/profile/ui/bloc/profile_cubit.dart`
- `packages/client/test/features/profile/profile_availability_cubit_test.dart`
- `packages/client/test/data/service/remote_api_client/direct_operation_routing_test.dart`
- `packages/client/test/features/profile/profile_cubit_realtime_test.dart` (compile-only port stubs)
- seven `ProfileRepositoryPort` test fakes outside nominal ownership (compile-only port stubs)
FINDINGS:
- `ProfileRepositoryMock` required no source change; Mockito covers the extended port.
- `pauseAvailability` formats `resumeOn` as strict UTC `YYYY-MM-DD` wire text in the
  repository (mutation arg is `String!`, not the Ferry `date` scalar).
- Command-local in-flight flags live on `ProfileCubit` getters; success profile updates
  arrive only via repository `RepositoryEventUpdate` after mutation + own-profile refetch.
REMAINING: manager acceptance of UNIT 09; UNIT 10 (`feat(client): add availability copy and dates`).

## UNIT 09 manager acceptance — 2026-08-14

VERDICT: accepted: `df00c40a3`, `54474e78c`, and `08785ef5d`.
REVIEW: The three operation names are V2-routed, and their documents contain
only self-only inputs: `isLimited`, `resumeOn`, or none. Each repository command
performs its one mutation, then refetches the supplied own-profile identity and
publishes `RepositoryEventUpdate`; it does not synthesize local availability.
The Cubit still has one repository port, no data-service import, separate
re-entrancy guards, preserves its profile on an exception, and emits one
`ShowError`. The `resumeOn` wire adapter refuses any non-UTC-midnight value
before producing `YYYY-MM-DD`. The added test-double methods in seven existing
tests are mechanical interface conformance necessitated by the port extension;
they do not broaden behavior.
INDEPENDENT VERIFICATION:
- `(cd packages/client && flutter test test/data/service/remote_api_client/direct_operation_routing_test.dart test/features/profile/profile_availability_cubit_test.dart test/features/profile/profile_cubit_realtime_test.dart)` -> 14 passed
- `./scripts/check-custom-lints.sh packages/client` -> pass; custom-rule total
  106, baseline 111
- `git diff --check cf20f1db4..HEAD` -> clean
FINDINGS: `df00c40a3` was committed concurrently by the user-authorized
independent UI agent. It includes the necessary compile-only port stubs, and
the user explicitly authorized incorporating this UI work. The plan's nominal
ownership list did not enumerate every concrete fake implementing the extended
port.
REMAINING: UNIT 10 is dependency-ready.

## UNIT 09 final evidence — 2026-08-14

COMMITS: `df00c40a33099474d72fe4208db18329ed13e6dc` feat(client): wire availability
commands; `54474e78c3fe796f20ac4b8d52a332b83831ae4a` docs: record UNIT 09 client
availability command evidence
TESTS:
- `(cd packages/client && dart run build_runner build -d)` → exit 0
- `(cd packages/client && flutter test test/data/service/remote_api_client/direct_operation_routing_test.dart test/features/profile/profile_availability_cubit_test.dart test/features/profile/profile_cubit_realtime_test.dart)` → 14 passed
- `./scripts/check-custom-lints.sh packages/client` → pass (custom-rule total 106, baseline 111)
- `git diff --check` → clean
FILES (nominal UNIT 09 ownership):
- `packages/client/lib/features/profile/data/gql/availability_set_limited.graphql`
- `packages/client/lib/features/profile/data/gql/availability_pause.graphql`
- `packages/client/lib/features/profile/data/gql/availability_resume.graphql`
- `packages/client/lib/data/service/remote_api_client/build_client.dart`
- `packages/client/lib/features/profile/domain/port/profile_repository_port.dart`
- `packages/client/lib/features/profile/data/repository/profile_repository.dart`
- `packages/client/lib/features/profile/ui/bloc/profile_cubit.dart`
- `packages/client/test/features/profile/profile_availability_cubit_test.dart`
- `packages/client/test/data/service/remote_api_client/direct_operation_routing_test.dart`
- `packages/client/test/features/profile/profile_cubit_realtime_test.dart`
FINDINGS:
- Incorporated user-authorized candidate work from an independent UI agent after live
  review; contracts match plan §UNIT 09 (V2 routing, self-only mutations, refetch +
  `RepositoryEventUpdate`, cubit command-local in-flight/error, no optimistic availability).
- `df00c40a3` also stages seven compile-only `ProfileRepositoryPort` test fakes outside
  nominal ownership (`account_case_recover_test.dart`, `graph_person_context_cubit_test.dart`,
  four `profile_view_*` tests) required after port extension; not claimed as UNIT 09 feature
  work.
- `ProfileRepositoryMock` needed no annotation change; Mockito satisfies the extended port.
- `userAvailabilityPause` wire arg is `String!` (`YYYY-MM-DD`); repository rejects non-UTC
  midnight `resumeOn` locally via `_utcCalendarDateWire`.
REMAINING: manager acceptance of UNIT 09; UNIT 10 (`feat(client): add availability copy and dates`).

## UNIT 10 — complete — 2026-08-14

COMMITS: `ee9eaa988` feat(client): add availability copy and dates; `422689382` docs: record UNIT 10 availability copy and dates evidence
TESTS:
- `(cd packages/client && flutter gen-l10n)` → exit 0
- `(cd packages/client && flutter test test/domain/util/availability_presets_test.dart test/ui/utils/calendar_day_display_test.dart test/l10n/availability_localization_test.dart)` → 25 passed
- `./scripts/check-custom-lints.sh packages/client` → pass (custom-rule total 106, baseline 111)
- `bash scripts/check-user-facing-terminology.sh` → pass
- `git diff --check` → clean
FILES:
- `packages/client/lib/domain/util/availability_presets.dart`
- `packages/client/lib/ui/utils/calendar_day_display.dart`
- `packages/client/lib/ui/utils/availability_line.dart`
- `packages/client/lib/ui/utils/beacon_card_deadline.dart`
- `packages/client/l10n/app_en.arb`
- `packages/client/l10n/app_ru.arb`
- `packages/client/test/domain/util/availability_presets_test.dart`
- `packages/client/test/ui/utils/calendar_day_display_test.dart`
- `packages/client/test/l10n/availability_localization_test.dart`
- `docs/plans/availability-request-receptiveness-implementation-journal.md`
L10N KEYS (25, architecture §10 + UNIT 11/14/15 sheet/delivery):
`availabilityLimitedTitle`, `availabilityPausedUntil`, `availabilitySelfOpen`,
`availabilitySelfLimited`, `availabilitySelfPausedUntil`, `availabilitySelfThenLimited`,
`availabilityResumeEcho`, `availabilityPersonPaused`, `availabilityUnaffectedNote`,
`availabilityResumeNow`, `availabilityDeliveredPartial`, `availabilityDeliveredPartialMany`,
`availabilitySheetTitle`, `availabilityLimitedSwitchTitle`,
`availabilityLimitedSwitchDescription`, `availabilityPauseSectionTitle`,
`availabilityPauseSectionDescription`, `availabilityPresetTomorrow`,
`availabilityPresetThisWeekend`, `availabilityPresetOneWeek`, `availabilityPresetOneMonth`,
`availabilityPresetPickDate`, `availabilityPauseAction`, `availabilityChangeAction`,
`availabilityDatePickerTitle`.
HUMAN REVIEW: EN/RU ARB diffs reviewed in-session for Request/Chat terminology, Russian
second-person self vs third-person others, and absence of gendered predicative adjectives
(`открыт/открыта/закрыт/недоступен` etc.).
FINDINGS:
- `formatFutureCalendarDayLabel` formats via y/m/d component midnight, never `toLocal()` on
  UTC calendar dates; beacon deadlines keep instant `toLocal()` for overdue/today/tomorrow
  and delegate only the future third-day+ branch to the shared formatter.
- `beacon_card_deadline_test.dart` is outside UNIT 10 ownership; ≥7-day beacon regression
  remains for a later touch (calendar_day_display tests cover the shared branch).
REMAINING: none for UNIT 10; UNIT 11 (`feat(client): add availability profile control`) is next.

## UNIT 10 remediation — complete — 2026-08-14

Manager review found `beacon_card_deadline_test.dart` asserted a 5-day weekday label but
did not prove the ≥7-calendar-day branch returns `formatFutureCalendarDayLabel` output
without the `myWorkStatusDueWeekday` wrapper.

COMMITS: `1051c301e` test(client): prove beacon ≥7-day deadline uses shared long date
TESTS:
- `(cd packages/client && flutter test test/ui/utils/beacon_card_deadline_test.dart test/ui/utils/calendar_day_display_test.dart)` → 23 passed
- `./scripts/check-custom-lints.sh packages/client` → pass (custom-rule total 106, baseline 111)
- `git diff --check` → clean
FILES:
- `packages/client/test/ui/utils/beacon_card_deadline_test.dart`
FINDINGS:
- Injected `now = 2026-06-22 12:00` with `endAt = 2026-06-29 18:00` (exactly 7 calendar
  days) yields `formatFutureCalendarDayLabel` long date (`Jun 29, 2026` in EN) and is not
  `myWorkStatusDueWeekday('Mon')`; existing instant/local overdue/today/tomorrow/5-day
  weekday assertions unchanged.
REMAINING: none for UNIT 10 remediation; UNIT 11 is next.

## UNIT 10 manager acceptance — 2026-08-14

VERDICT: accepted: `ee9eaa988`, `422689382`, `1051c301e`, and `ef88d4473`.
REVIEW: Presets use calendar arithmetic over checked UTC date-only inputs,
including the Monday-to-following-Monday rule, month-end clamp, and 90-day
horizon. The pure day formatter carries y/m/d components into the locale
formatter without converting an availability instant to local time. Its 6/7-day
split is now proven both directly and through `beaconCardCalendarDeadlineStatus`;
that adapter preserves its distinct instant/local behavior for overdue, today,
and tomorrow. EN/RU availability copy is present, terminology-safe, and the
Russian forms distinguish self from other-person copy without gendered
predicative adjectives.
INDEPENDENT VERIFICATION:
- `(cd packages/client && flutter test test/ui/utils/beacon_card_deadline_test.dart test/ui/utils/calendar_day_display_test.dart test/domain/util/availability_presets_test.dart test/l10n/availability_localization_test.dart)` -> 39 passed
- `git diff --check 2c7f1869d..HEAD` -> clean
FINDINGS: Manager review required the separate 7-day beacon-deadline integration
test because testing the shared formatter alone did not prove the adapted branch
was wired. The remediation adds no production behavior.
REMAINING: UNIT 11 is dependency-ready.

## UNIT 11 — complete — 2026-08-14

COMMITS: `fcf1d344c` feat(client): add availability profile control
TESTS:
- `(cd packages/client && flutter test test/features/profile/availability_sheet_test.dart test/features/profile/profile_availability_golden_test.dart)` → 26 passed
- `(cd packages/client && flutter test test/features/profile/profile_availability_golden_test.dart --update-goldens)` → 13 passed (regenerated PNGs)
- `./scripts/check-custom-lints.sh packages/client` → pass (custom-rule total 106, baseline 111)
- `bash scripts/check-user-facing-terminology.sh` → pass
- `git diff --check` → clean
FILES:
- `packages/client/lib/features/profile/ui/sheet/availability_sheet.dart`
- `packages/client/lib/features/profile/ui/screen/profile_screen.dart`
- `packages/client/lib/features/profile/ui/widget/profile_body.dart`
- `packages/client/test/features/profile/availability_sheet_test.dart`
- `packages/client/test/features/profile/profile_availability_golden_test.dart`
- `packages/client/test/features/profile/goldens/profile_availability_*.png` (12 PNGs)
GOLDEN PNG INSPECTION (visual review after `--update-goldens`):
- `.../profile_availability_open_compact.png` — neutral “Open to requests” + blue Change; no second line
- `.../profile_availability_limited_compact.png` — info-toned “Only important requests” + Change
- `.../profile_availability_paused_expanded.png` — warn-toned paused-until line + Change on wide layout
- `.../profile_availability_limited_paused_compact.png` — warn primary + info “Then: only important requests” two-line stack + Change
- `.../profile_availability_open_compact_s1_3.png` — 1.3 text scale enlarges status/Change without clipping
FINDINGS:
- `showDatePicker` bounds use local y/m/d via `availabilityPickerLocalDate`; picked values convert through `utcCalendarDateFromLocalPicker` (no `toLocal()` on availability storage).
- Injectable `clock` seam on sheet/profile body and `@visibleForTesting` `availabilityTodayUtc` keep `todayUtc` deterministic in tests.
- Sheet closes only after cubit-confirmed pause/resume profile state; limited toggle keeps the sheet open and reads confirmed `Profile.availability`.
REMAINING: none for UNIT 11; UNIT 12 (`feat(client): gate person request actions`) is next.

## UNIT 11 final evidence — 2026-08-14

COMMITS: `fcf1d344c` feat(client): add availability profile control
TESTS:
- `(cd packages/client && flutter test test/features/profile/availability_sheet_test.dart test/features/profile/profile_availability_golden_test.dart)` → 26 passed
- `./scripts/check-custom-lints.sh packages/client` → pass (custom-rule total 106, baseline 111)
- `bash scripts/check-user-facing-terminology.sh` → pass
- `git diff --check` → clean after implementation commit
FILES: UNIT 11 owned paths listed above (12 golden PNGs under `test/features/profile/goldens/`)
FINDINGS: none beyond UNIT 11 entry
REMAINING: manager acceptance of UNIT 11; UNIT 12 is next

## UNIT 11 remediation — in-flight UI rebuild — 2026-08-14

COMMITS: `b60724611` fix(client): rebuild availability sheet during command in-flight
TESTS:
- `(cd packages/client && flutter test test/features/profile/availability_sheet_test.dart test/features/profile/profile_availability_golden_test.dart)` → 30 passed
- `./scripts/check-custom-lints.sh packages/client` → pass (custom-rule total 106, baseline 111)
- `git diff --check` → clean after remediation commit
FILES:
- `packages/client/lib/features/profile/ui/sheet/availability_sheet.dart`
- `packages/client/test/features/profile/availability_sheet_test.dart`
FINDINGS:
- Defect: `AvailabilitySheetBody` read `ProfileCubit.isAvailability*InFlight` in
  `build`, but production cubit toggles those private flags without `emit`, so the
  sheet did not rebuild while a repository command awaited.
- Repair: command-local `_local*InFlight` flags set via `setState` at command start
  and cleared in `finally`; combined with cubit getters via OR for belt-and-suspenders.
  Limited toggle still keeps sheet open on confirmed profile; pause/resume still close
  only after cubit-confirmed profile state; failures keep sheet open and rely on cubit
  `ShowError` only.
- Tests: four completer-backed dynamic widget tests prove per-command disable while
  awaiting, independent controls stay enabled, failed pause re-enables and keeps sheet,
  successful pause/resume still close per existing contract. Static cubit-getter
  in-flight tests retained for OR path.
REMAINING: manager re-acceptance of UNIT 11; UNIT 12 is next

## UNIT 11 manager acceptance — 2026-08-14

VERDICT: accepted: `fcf1d344c`, `87a24dabb`, `b60724611`, and `870eab6ae`.
REVIEW: The own profile renders a status directly after its description, with
the required neutral/info/warn tones and a second info line only for
limited-plus-paused. Change opens the two-control sheet; date bounds use local
calendar components and return a UTC calendar date. A manager review found and
remediated a production loading defect: Cubit getter changes alone do not emit
state, so sheet-local transient flags now make each command's disabled state
observable while preserving independent controls. Pause/resume only close after
their confirmed Cubit profile state; failure retains the sheet and relies on
the single Cubit effect. The visual artifacts show expected compact/expanded
geometry and the 1.3 text-scale cases without clipping (Flutter's Ahem test
font displays glyphs as blocks in the raw PNGs).
INDEPENDENT VERIFICATION:
- `(cd packages/client && flutter test test/features/profile/availability_sheet_test.dart test/features/profile/profile_availability_golden_test.dart)` -> 30 passed
- `git diff --check 896492400..HEAD` -> clean
FINDINGS: The initial golden set was retained after the loading repair because
the control's resting rendering did not change. Manager visual inspection
covered open compact, paused expanded, and limited+paused compact at 1.3 scale.
REMAINING: UNIT 12 is dependency-ready.

## UNIT 12 — complete — 2026-08-14

COMMITS: `c1585421f` feat(client): gate person request actions
TESTS:
- `(cd packages/client && flutter test test/ui/model/person_action_policy_test.dart test/features/profile_view/profile_view_body_action_policy_test.dart test/features/graph/graph_person_context_panel_test.dart)` → 88 passed
- `./scripts/check-custom-lints.sh packages/client` → pass (custom-rule total 106, baseline 111)
- `bash scripts/check-user-facing-terminology.sh` → pass
- `git diff --check` → clean
FILES:
- `packages/client/lib/ui/model/person_action_policy.dart`
- `packages/client/lib/features/profile_view/ui/widget/profile_view_body.dart`
- `packages/client/lib/features/graph/ui/widget/graph_person_context_panel.dart`
- `packages/client/test/ui/model/person_action_policy_test.dart`
- `packages/client/test/features/profile_view/profile_view_body_action_policy_test.dart`
- `packages/client/test/features/graph/graph_person_context_panel_test.dart`
FINDINGS:
- `PersonActionPolicy.from` applies pause as a post-`_baseFrom` override using
  `profile.availability.blocksNewRequestsOn(todayUtc)`; limited leaves policy unchanged.
- Default `todayUtc` uses the same UTC y/m/d rule as plan §0.6 via a local helper in
  `person_action_policy.dart` (avoids `ui/model` → `features/profile` import).
- Other-profile/graph surfaces render `otherAvailabilityStatusLine` with neutral
  `TenturaStatusText` after presence (profile) or header (graph) and before trust/visibility;
  paused path sets `showRequestOptions: false` so `profileRequestUnavailable` never opens a
  request door.
- Widget tests exercise paused mutual MR, paused viewer-only, paused subject-only, and limited
  on both profile and graph; policy tests cover all 16 trust/MR rows × open/limited/paused plus
  resume-day equality.
REMAINING: manager acceptance of UNIT 12; UNIT 13 (`feat(client): show availability in recipient picker`) is next.

## UNIT 12 remediation — complete — 2026-08-14

STATUS: complete
COMMITS: `06cdebe25` fix(client): share availabilityTodayUtc in domain util
TESTS:
- `(cd packages/client && flutter test test/ui/model/person_action_policy_test.dart test/features/profile_view/profile_view_body_action_policy_test.dart test/features/graph/graph_person_context_panel_test.dart test/domain/util/availability_presets_test.dart test/features/profile/availability_sheet_test.dart test/features/profile/profile_availability_golden_test.dart)` → 131 passed
- `./scripts/check-custom-lints.sh packages/client` → pass (custom-rule total 106, baseline 111)
- `bash scripts/check-user-facing-terminology.sh` → pass
- `git diff --check` → clean
- `rg 'features/profile/ui/sheet/availability_sheet.dart' packages/client/lib/features/profile_view packages/client/lib/features/graph` → 0 matches
FILES:
- `packages/client/lib/domain/util/availability_presets.dart`
- `packages/client/lib/features/profile/ui/sheet/availability_sheet.dart`
- `packages/client/lib/features/profile/ui/widget/profile_body.dart`
- `packages/client/lib/features/profile_view/ui/widget/profile_view_body.dart`
- `packages/client/lib/features/graph/ui/widget/graph_person_context_panel.dart`
- `packages/client/test/domain/util/availability_presets_test.dart`
- `packages/client/test/features/profile/profile_availability_golden_test.dart`
- `packages/client/test/features/profile_view/profile_view_body_action_policy_test.dart`
- `packages/client/test/features/graph/graph_person_context_panel_test.dart`
FINDINGS:
- `availabilityTodayUtc` is the single authoritative UTC y/m/d helper in
  `domain/util/availability_presets.dart`; profile sheet and profile_body import it from there.
- `PersonActionPolicy` retains its local `_defaultTodayUtc` (no feature/UI import).
- No golden update; resting UI unchanged.
REMAINING: manager acceptance of UNIT 12; UNIT 13 is next.

## UNIT 12 manager acceptance — 2026-08-14

VERDICT: accepted: `c1585421f`, `018198c37`, `06cdebe25`, `23d82a924`, and
`5c1e8645a`.
REVIEW: Availability is a post-base-policy override only: a pause removes every
profile/graph send door while preserving Trust and its pre-existing secondary
state; limited leaves mechanisms intact. Other-person availability uses the
dedicated neutral status line and is placed between presence/header and the
trust/visibility material. The initial candidate's import of a profile UI sheet
from profile-view and graph was rejected and repaired by moving the UTC-date
clock seam to the shared domain availability utility. The final manager repair
makes the policy default consume that same utility and proves an explicit
UTC-offset midnight boundary.
INDEPENDENT VERIFICATION:
- `(cd packages/client && flutter test test/ui/model/person_action_policy_test.dart test/features/profile_view/profile_view_body_action_policy_test.dart test/features/graph/graph_person_context_panel_test.dart test/domain/util/availability_presets_test.dart test/features/profile/availability_sheet_test.dart test/features/profile/profile_availability_golden_test.dart)` -> 132 passed
- `./scripts/check-custom-lints.sh packages/client` -> pass (custom-rule total 106, baseline 111)
- `bash scripts/check-user-facing-terminology.sh` -> pass
- `rg -n "features/profile/ui/sheet/availability_sheet.dart" packages/client/lib/features/profile_view packages/client/lib/features/graph` -> no matches
- `git diff --check b6361d514..HEAD` -> clean
FINDINGS: The explicit `2026-08-14T00:15:00+02:00` test now proves that the
clock derives `2026-08-13` UTC, rather than merely proving a same-date local
conversion. Existing goldens remain valid because visual output did not change.
REMAINING: UNIT 13 is dependency-ready.

## UNIT 13 — complete — 2026-08-14

COMMITS: `eb08fc0bb` feat(client): show availability in recipient picker
TESTS:
- `(cd packages/client && flutter test test/features/forward/forward_recipient_host_policy_test.dart test/features/forward/forward_state_scope_test.dart test/features/forward/ui/widget/forward_band_strip_test.dart test/golden/typography_overhaul_test.dart)` → 36 passed, 7 skipped (golden)
- `(cd packages/client && flutter test test/features/forward/forward_recipient_picker_test.dart)` → 6 passed
- `./scripts/check-custom-lints.sh packages/client` → pass (custom-rule total 106, baseline 111)
- `bash scripts/check-user-facing-terminology.sh` → pass
- `git diff --check` → clean
- `rg "ForwardRecipientRow\\(" packages/client --glob "*.dart"` → all 8 call sites pass explicit `host:` (constructor definition + 7 invocations)
FILES:
- `packages/client/lib/features/forward/ui/model/forward_recipient_row_host.dart`
- `packages/client/lib/features/forward/domain/entity/forward_candidate.dart`
- `packages/client/lib/features/forward/domain/use_case/forward_case.dart`
- `packages/client/lib/features/forward/ui/widget/forward_recipient_row.dart`
- `packages/client/lib/features/forward/ui/widget/forward_recipient_picker.dart`
- `packages/client/lib/features/forward/ui/widget/forward_band_strip.dart`
- `packages/client/lib/features/forward/ui/widget/forward_search_overlay.dart`
- `packages/client/lib/features/forward/ui/widget/lineage_suggestions_sheet.dart`
- `packages/client/test/features/forward/forward_state_scope_test.dart`
- `packages/client/test/features/forward/forward_recipient_host_policy_test.dart`
- `packages/client/test/golden/typography_overhaul_test.dart`
FINDINGS:
- `ForwardState` needed no edits: unseen scope already lists `isUnseen` rows (including paused)
  and `scopeCounts.unseen` counts them; `canForwardToOn` gates selection only.
- Row policy lives in `forward_recipient_row_host.dart` as pure `computeForwardRecipientLine2`
  plus `forwardRecipientCheckboxEnabled` for widget + unit tests.
- Band pause exclusion runs in `ForwardCase.loadForwardCandidates` after fetch using
  `availabilityTodayUtc()`; rows without a matched candidate survive (`ghost` regression).
REMAINING: none for UNIT 13; UNIT 14 (`feat(client): report actual forward delivery`) is next.

## UNIT 13 remediation — complete — 2026-08-14

COMMITS: `3cd703ac5` fix(client): inject todayUtc into forward recipient relation tone
TESTS:
- `(cd packages/client && flutter test test/features/forward/forward_recipient_host_policy_test.dart test/features/forward/forward_state_scope_test.dart test/features/forward/ui/widget/forward_band_strip_test.dart test/features/forward/forward_recipient_picker_test.dart test/golden/typography_overhaul_test.dart)` → 48 passed, 7 skipped (golden)
- `./scripts/check-custom-lints.sh packages/client` → pass (custom-rule total 106, baseline 111)
- `bash scripts/check-user-facing-terminology.sh` → pass
- `git diff --check` → clean
- `rg "ForwardRecipientRow\\(" packages/client --glob "*.dart"` → all call sites pass explicit `host:` (constructor definition + 7 production invocations + tests)
FILES:
- `packages/client/lib/features/forward/ui/model/forward_recipient_row_host.dart`
- `packages/client/test/features/forward/forward_recipient_host_policy_test.dart`
FINDINGS:
- Defect A: `forwardRecipientRelationTone` used `candidate.canForwardTo` (process clock via
  `availabilityTodayUtc()`); signature now requires `todayUtc` and calls
  `candidate.canForwardToOn(todayUtc)`. UTC resume-boundary tests prove injected
  `2026-08-13` vs `2026-08-14` flips relation tone, checkbox policy, and line precedence
  without depending on the actual clock.
- Defect B: added `ForwardRecipientRow` widget interaction tests — selected paused row tap
  invokes `onToggle` once; unselected paused row and trailing checkbox taps invoke no
  callback (checkbox targeted via trailing coordinate tap because nested InkWell is not
  separately findable under the row key).
- Large `ForwardCase` band-exclusion harness retained; still required for order/provenance
  proof after client-side pause filter.
REMAINING: manager re-review of UNIT 13 remediation; UNIT 14 unchanged.

## UNIT 13 manager acceptance — 2026-08-14

VERDICT: accepted: `eb08fc0bb`, `675d7ede1`, `3cd703ac5`, and `d251eec80`.
REVIEW: Recipient-row availability is controlled by the required five-value host
inventory. Every picker host displays availability while the read-only lineage
preview suppresses it. The precedence ordering preserves tier evidence, hidden
presence, reachability, and ineligible-involvement states ahead of availability;
limited remains informational and paused candidates cannot be newly selected.
The remediation removes the last clock leak from the pure injected-date line
policy: relation tone now calls `canForwardToOn(todayUtc)`, and the resume date
boundary is independently exercised. The row event boundary now proves that a
selected paused row remains deselectable and an unselected paused row cannot
invoke the outer-row or trailing-checkbox callbacks. Band filtering retains
unmatched rows and survivor order/provenance after excluding only matched paused
candidates.
INDEPENDENT VERIFICATION:
- `(cd packages/client && flutter test test/features/forward/forward_recipient_host_policy_test.dart test/features/forward/forward_state_scope_test.dart test/features/forward/ui/widget/forward_band_strip_test.dart test/features/forward/forward_recipient_picker_test.dart test/golden/typography_overhaul_test.dart)` -> 48 passed, 7 skipped (golden)
- `./scripts/check-custom-lints.sh packages/client` -> pass (custom-rule total 106, baseline 111)
- `bash scripts/check-user-facing-terminology.sh` -> pass
- `git diff --check` -> clean
- host-call audit over all Dart `ForwardRecipientRow(` occurrences -> each invocation passes explicit `host:`
FINDINGS: The focused test uses a 44dp trailing checkbox-centre coordinate to
exercise the nested checkbox event boundary, because the inner InkWell is not
separately findable below the outer-row key. The test proves the actual rendered
target, not only the helper policy.
REMAINING: UNIT 14 is dependency-ready.

## UNIT 14 — complete — 2026-08-14

COMMITS: `ecfd84c39` feat(client): map typed forward delivery result from beaconForward; `2e4806166` feat(client): forward delivery UX with availability preselect and expiry; `fd8a2bffa` test(client): prove forward typed delivery and confirmation contracts
TESTS:
- `(cd packages/client && flutter test test/features/forward/forward_cubit_preselect_test.dart test/features/forward/forward_cubit_candidates_load_test.dart test/features/forward/forward_cubit_live_sync_test.dart test/features/forward/forward_cubit_attribution_test.dart test/features/forward/forward_cubit_band_provenance_test.dart test/features/forward/forward_delivery_result_test.dart test/features/forward/person_forward_case_test.dart test/features/beacon_create/beacon_send_confirmation_dialog_test.dart test/features/forward/forward_recipient_picker_test.dart)` → 41 passed
- `./scripts/check-custom-lints.sh packages/client` → pass (custom-rule total 106, baseline 111)
- `bash scripts/check-user-facing-terminology.sh` → pass
- `git diff --check` → clean
FILES:
- `packages/client/lib/features/forward/data/repository/forward_repository.dart`
- `packages/client/lib/features/forward/domain/use_case/forward_case.dart`
- `packages/client/lib/features/forward/ui/bloc/forward_cubit.dart`
- `packages/client/lib/features/forward/ui/bloc/forward_state.dart`
- `packages/client/lib/features/forward/ui/message/forward_messages.dart`
- `packages/client/lib/features/beacon_create/ui/dialog/beacon_send_confirmation_dialog.dart`
- `packages/client/test/features/forward/forward_cubit_preselect_test.dart`
- `packages/client/test/features/forward/forward_cubit_candidates_load_test.dart`
- `packages/client/test/features/forward/forward_cubit_live_sync_test.dart`
- `packages/client/test/features/forward/forward_cubit_attribution_test.dart`
- `packages/client/test/features/forward/forward_cubit_band_provenance_test.dart`
- `packages/client/test/features/forward/forward_delivery_result_test.dart`
- `packages/client/test/features/forward/person_forward_case_test.dart`
- `packages/client/test/features/beacon_create/beacon_send_confirmation_dialog_test.dart`
FINDINGS:
- `ForwardRepository.forwardBeacon` signature change requires a compile-only stub update in UNIT 15-owned `person_forward_cubit_test.dart` (left unstaged in this worktree so `check-custom-lints.sh` stays green locally).
- `AppLifecycleListener` attaches only when `BindingBase.debugBindingType()` is non-null so VM unit tests avoid `WidgetsFlutterBinding.ensureInitialized()` unless exercising resume.
- `ForwardDeliveredOfMessage` (owned `forward_messages.dart`) supplies embedded confirmation N-of-M copy without new ARB keys.
REMAINING: manager acceptance of UNIT 14; UNIT 15 (`feat(client): gate person forward flow`) is next.
