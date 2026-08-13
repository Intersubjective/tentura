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
- [ ] **UNIT 07 — Server PostgreSQL/concurrency/API proof** — depends: 04–06 — commit:
  `test(server): prove availability invariants`
- [ ] **UNIT 08 — Client schema, date scalar, entities, read parity** — depends: 04–06 — commit:
  `feat(client): map availability data`
- [ ] **UNIT 09 — Client availability command repository and Cubit** — depends: 05, 08 — commit:
  `feat(client): wire availability commands`
- [ ] **UNIT 10 — Calendar presets, formatting, localization** — depends: 08 — commit:
  `feat(client): add availability copy and dates`
- [ ] **UNIT 11 — Own-profile control and status** — depends: 09–10 — commit:
  `feat(client): add availability profile control`
- [ ] **UNIT 12 — Other-profile and graph policy/rendering** — depends: 10 — commit:
  `feat(client): gate person request actions`
- [ ] **UNIT 13 — Picker host policy, row precedence, band exclusion** — depends: 08, 10 —
  commit: `feat(client): show availability in recipient picker`
- [ ] **UNIT 14 — Picker preselection, expiry refresh, typed delivery UX** — depends: 06, 08,
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
